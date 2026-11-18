module Api
  module V1
    class ItemsController < ApplicationController
      MAX_RESCUE_CARDS = 3

      rescue_from Items::Resolve::UnknownOutcome do
        render json: { error: I18n.t("items.unknown_outcome") }, status: :unprocessable_content
      end

      rescue_from Items::Undo::NotUndoable do
        render json: { error: I18n.t("items.not_undoable") }, status: :unprocessable_content
      end

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
          # A kitchen that has never captured anything gets one way in from
          # Today itself (doc 2 §2.7: first inventory inside 180 seconds).
          has_captured: current_household.captures.exists?,
          as_of: Date.current
        }
      end

      def show
        render json: item_json(current_household.items.find(params[:id]))
      end

      # Correction has to be cheaper than capture (doc 2 §2.9 rule 4), and every
      # correction teaches the dictionary so the same line parses free next time.
      def update
        item = Items::Correct.call(item: current_household.items.find(params[:id]), changes: item_params)
        render json: item_json(item.reload)
      end

      # A line removed as read wrong. What the model said about it is taken
      # back out of this kitchen's dictionary too, or the mistake would be
      # free to repeat — and count as a vote for every kitchen.
      def destroy
        item = current_household.items.find(params[:id])
        ProductAlias.forget!(household: current_household, raw_text: item.raw_text)
        item.destroy!
        head :no_content
      end

      # One tap ends the task. Every outcome is a single POST: no body beyond
      # `days` for a snooze and `to` for a move.
      def resolve
        item = Items::Resolve.call(item: current_household.items.find(params[:id]),
                                   outcome: params[:outcome], days: params[:days], to: params[:to],
                                   source: params[:source], start_percent: params[:start_percent])
        render json: item_json(item.reload)
      end

      # Takes back the tap just made — a mis-tap on a list that reorders itself.
      def undo
        item = Items::Undo.call(item: current_household.items.find(params[:id]))
        render json: item_json(item.reload)
      end

      # The slider opened this pack, and the thumb is back at the percent that
      # drag started from. A pack that was already open is left as it is.
      def revert_open
        item = Items::RevertSliderOpen.call(item: current_household.items.find(params[:id]),
                                             percent: params.require(:percent))
        render json: item_json(item.reload)
      end

      # One slider per name in the Kitchen. The client sends the ids it grouped
      # under that line; scoping through current_household makes a foreign id a
      # no-op rather than a leak.
      def level
        packs = Inventory::SetLevel.call(household: current_household,
                                         ids: params.require(:ids), level: params.require(:level))
        render json: { items: packs.map { |item| item_json(item) } }
      end

      private

      def item_params
        params.require(:item).permit(:display_name, :canonical_name, :category, :storage,
                                     :quantity, :unit, :date_label_value, :date_label_type)
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
          product_id: item.product_id,
          category: item.category,
          raw_text: item.raw_text,
          quantity: item.quantity&.to_f,
          amount_left: item.amount_left,
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
          high_risk: item.high_risk?,
          safety_date: item.safety_date?,
          added_by_name: item.added_by_name
        }
      end
    end
  end
end
