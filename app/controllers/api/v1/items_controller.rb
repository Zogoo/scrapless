module Api
  module V1
    class ItemsController < ApplicationController
      MAX_RESCUE_CARDS = 3

      # The Today screen: one question answered, "what should I do about food
      # today?". Auto-retirement runs first so the answer is never polluted by
      # food we stopped believing in.
      def index
        Inventory::Retire.call(household: current_household)
        scored = Freshness::RiskScorer.call(items: current_household.items.active.by_urgency.to_a)

        use_first = scored.select(&:worth_showing?).first(MAX_RESCUE_CARDS)
        rest = scored - use_first

        render json: {
          use_first: use_first.map { |s| scored_json(s) },
          fine_for_now: rest.reject { |s| s.phase == "ghost" }.map { |s| scored_json(s) },
          probably_gone: rest.select { |s| s.phase == "ghost" }.map { |s| scored_json(s) },
          sweep_count: scored.count(&:ambiguous?),
          as_of: Date.current
        }
      end

      def show
        render json: item_json(current_household.items.find(params[:id]))
      end

      # Correction has to be cheaper than capture (doc 2 §2.9 rule 4), and every
      # correction teaches the dictionary so the same line parses free next time.
      def update
        item = current_household.items.find(params[:id])
        item.update!(item_params)

        if item.raw_text.present? && item.saved_change_to_attribute?(:display_name)
          ProductAlias.record_correction!(
            raw_text: item.raw_text, canonical_name: item.canonical_name,
            category: item.category, merchant: item.capture&.merchant
          )
        end

        log_event(item, "corrected", changed: item.previous_changes.keys - %w[updated_at lock_version])
        render json: item_json(item.reload)
      end

      def destroy
        item = current_household.items.find(params[:id])
        item.destroy!
        head :no_content
      end

      # One tap ends the task. Every outcome is a single POST with no body.
      def resolve
        item = current_household.items.find(params[:id])
        outcome = params[:outcome].to_s

        case outcome
        when "used"    then finish(item, state: "rescued", kind: "used")
        when "wasted"  then finish(item, state: "wasted", kind: "wasted")
        when "partial" then partial_use(item)
        when "froze"   then freeze_item(item)
        when "opened"  then open_item(item)
        when "snooze"  then snooze(item)
        else return render json: { error: "unknown outcome" }, status: :unprocessable_content
        end

        render json: item_json(item.reload)
      end

      private

      def item_params
        params.require(:item).permit(:display_name, :canonical_name, :category, :storage,
                                     :quantity, :unit, :date_label_value, :date_label_type)
      end

      def finish(item, state:, kind:)
        item.update!(state: state, resolved_at: Time.current)
        log_event(item, kind)
      end

      # Binary used/gone forces the user to lie, and the lie trains the priors
      # (doc 4 §4.14).
      #
      # Using half the spinach does not make the other half spoil faster, so the
      # window is left alone. What changed is how much is left — which the
      # presence model reads back off this event.
      def partial_use(item)
        item.update!(quantity: item.quantity ? (item.quantity / 2) : nil)
        log_event(item, "partial_use")
      end

      # Freezing is a lookup, not a multiplier: the window is recomputed for the
      # freezer from today, which is why storage_changed_at has to exist.
      def freeze_item(item)
        window = Freshness::Estimator.call(category: item.category, storage: "freezer",
                                           acquired_on: Date.current)
        item.update!(storage: "freezer", storage_changed_at: Time.current,
                     window_start: window.window_start, window_end: window.window_end,
                     confidence: window.confidence)
        log_event(item, "frozen")
      end

      def open_item(item)
        window = Freshness::Estimator.call(category: item.category, storage: item.storage,
                                           acquired_on: item.acquired_on, opened_on: Date.current)
        item.update!(opened_on: Date.current, window_end: window.window_end,
                     confidence: window.confidence)
        log_event(item, "opened")
      end

      # A "no" must not become a delete.
      def snooze(item)
        days = params.fetch(:days, 3).to_i.clamp(1, 30)
        item.update!(snoozed_until: Date.current + days)
        log_event(item, "snoozed", days: days)
      end

      def log_event(item, kind, meta = {})
        item.item_events.create!(household: current_household, kind: kind, at: Time.current,
                                 meta: meta.to_json)
      end

      def scored_json(scored)
        item_json(scored.item).merge(
          presence: scored.presence,
          spoilage: scored.spoilage,
          risk: scored.risk,
          phase: scored.phase,
          headline: Copy.headline(scored),
          alertable: scored.alertable?,
          life_fraction: scored.item.life_fraction.round(3)
        )
      end

      def item_json(item)
        {
          id: item.id,
          display_name: item.display_name,
          canonical_name: item.canonical_name,
          category: item.category,
          raw_text: item.raw_text,
          quantity: item.quantity&.to_f,
          unit: item.unit,
          storage: item.storage,
          acquired_on: item.acquired_on,
          window_start: item.window_start,
          window_end: item.window_end,
          days_left: item.days_left,
          confidence: item.confidence,
          state: item.state,
          opened_on: item.opened_on,
          snoozed_until: item.snoozed_until,
          high_risk: item.high_risk?
        }
      end
    end
  end
end
