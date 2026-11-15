module Items
  # One tap on a food: used, gone, half used, frozen, opened or "not now".
  #
  # Every outcome is recorded with the fields it changed as they were before,
  # so the very next tap can take it back (Items::Undo). One-tap actions on a
  # list that reorders itself will be mis-tapped; without an undo the mistake
  # is permanent, and it trains the priors (doc 4 §4.14).
  class Resolve < ApplicationService
    class UnknownOutcome < StandardError; end

    KINDS = { "used" => "used", "wasted" => "wasted", "partial" => "partial_use",
              "froze" => "frozen", "opened" => "opened", "snooze" => "snoozed" }.freeze

    # Everything an outcome may change, so undo can put it back exactly.
    TRACKED = %w[state resolved_at quantity amount_left storage storage_changed_at
                 window_start window_end confidence opened_on snoozed_until].freeze

    def initialize(item:, outcome:, days: nil)
      @item = item
      @outcome = outcome.to_s
      @days = days
    end

    def call
      kind = KINDS.fetch(@outcome) { raise UnknownOutcome, @outcome }
      before = @item.attributes.slice(*TRACKED)

      Item.transaction do
        send(:"apply_#{@outcome}")
        @item.save!
        @item.item_events.create!(household: @item.household, kind: kind, at: Time.current,
                                  meta: meta(before).to_json)
      end
      @item
    end

    private

    def meta(before)
      { before: before }.merge(@outcome == "snooze" ? { days: snooze_days } : {})
    end

    def apply_used = finish("rescued")
    def apply_wasted = finish("wasted")

    def finish(state)
      @item.assign_attributes(state: state, resolved_at: Time.current)
    end

    # Binary used/gone forces the user to lie (doc 4 §4.14). Using half the
    # spinach does not make the other half spoil faster, so the window stays;
    # what changed is how much is left, which the presence model reads back
    # off this event.
    def apply_partial
      @item.assign_attributes(quantity: @item.quantity && (@item.quantity / 2),
                              amount_left: (@item.amount_left / 2).round(2))
    end

    # Freezing is a lookup, not a multiplier: the window is recomputed for the
    # freezer from today, which is why storage_changed_at has to exist.
    def apply_froze
      rewindow(storage: "freezer", acquired_on: Date.current)
      @item.assign_attributes(storage: "freezer", storage_changed_at: Time.current)
    end

    # Opening restarts the clock on a short remaining life. Both ends of the
    # window move: keeping the old start broke the start <= end rule for any
    # food opened before its band had opened — which is most food.
    def apply_opened
      rewindow(storage: @item.storage, acquired_on: @item.acquired_on, opened_on: Date.current)
      @item.opened_on = Date.current
    end

    # A "no" must not become a delete.
    def apply_snooze
      @item.snoozed_until = Date.current + snooze_days
    end

    def snooze_days = (@days || 3).to_i.clamp(1, 30)

    def rewindow(**inputs)
      window = Freshness::Estimator.call(category: @item.category, **inputs)
      @item.assign_attributes(window_start: window.window_start, window_end: window.window_end,
                              confidence: window.confidence)
    end
  end
end
