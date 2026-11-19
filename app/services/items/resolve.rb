module Items
  # One tap on a food: used, gone, half used, frozen, opened, moved or "not now".
  #
  # Every outcome is recorded with the fields it changed as they were before,
  # so the very next tap can take it back (Items::Undo). One-tap actions on a
  # list that reorders itself will be mis-tapped; without an undo the mistake
  # is permanent, and it trains the priors (doc 4 §4.14).
  class Resolve < ApplicationService
    class UnknownOutcome < StandardError; end

    KINDS = { "used" => "used", "wasted" => "wasted", "partial" => "partial_use",
              "froze" => "frozen", "opened" => "opened", "snooze" => "snoozed",
              "moved" => "moved" }.freeze

    # Everything an outcome may change, so undo can put it back exactly.
    TRACKED = %w[state resolved_at quantity amount_left storage storage_changed_at
                 window_start window_end confidence opened_on snoozed_until].freeze

    def initialize(item:, outcome:, days: nil, to: nil, source: nil, start_percent: nil)
      @item = item
      @outcome = outcome.to_s
      @days = days
      @to = to.to_s
      @source = source.to_s
      @start_percent = start_percent
      # Into the freezer is freezing, whichever button said so: one event kind
      # and one window rule for it in the audit log.
      @outcome = "froze" if @outcome == "moved" && @to == "freezer"
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
      extra = {}
      extra[:days] = snooze_days if @outcome == "snooze"
      # The percent the thumb was on before this drag. A later release there
      # can undo the open after it has already been saved.
      percent = slider_start_percent
      unless percent.nil?
        extra[:source] = "slider"
        extra[:start_percent] = percent
      end
      extra[:amount] = @wasted_amount unless @wasted_amount.nil?
      { before: before }.merge(extra)
    end

    # nil becomes 0 via to_i, which would record a start the user never had.
    def slider_start_percent
      return nil unless @outcome == "opened" && @source == "slider"
      return nil unless @start_percent.to_s.match?(/\A\d{1,3}\z/)

      percent = @start_percent.to_i
      percent if (0..100).cover?(percent)
    end

    def apply_used = finish("rescued")

    # Thrown away is this one pack (the soonest, when a line groups several).
    # What was wasted is what was still left: a half-used pack wastes 1/2, not
    # a whole pack. quantity holds that amount. There is no waste screen; the
    # event's amount is the same number, for anything that counts later.
    def apply_wasted
      @wasted_amount = @item.amount_left.to_f.round(2)
      finish("wasted")
      @item.quantity = @wasted_amount
    end

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

    # Opening shortens the end already on the item, and only when the opened
    # life is sooner. Rebuilding from the category table first threw that end
    # away, so every open — including one the slider repeated — read as 3 days.
    # A pack that is already open is left alone; the slider may change its
    # amount and must not restart the clock. The start still has to move back
    # when the band has not begun, or start > end fails validation.
    def apply_opened
      return if @item.opened_on.present?

      opened = Date.current
      cap = opened + Freshness::Estimator.opened_days(category: @item.category, storage: @item.storage,
                                                      product: @item.product)
      @item.opened_on = opened
      @item.window_end = cap if @item.window_end.blank? || cap < @item.window_end
      @item.window_start = [ @item.window_start, opened, @item.window_end ].compact.min
      @item.window_start = [ @item.window_start, @item.acquired_on ].compact.max
      @item.window_end = [ @item.window_end, @item.window_start ].compact.max
    end

    # Somewhere else in the kitchen (into the freezer became "froze" above).
    # Out of the freezer is a thaw, which keeps only days
    # (Estimator::THAWED_DAYS). Otherwise a move never buys time: milk put in
    # the cupboard must not inherit the cupboard's generic six months, so the
    # band can only stay or come closer. Only freezing resets the clock.
    def apply_moved
      raise UnknownOutcome, @to unless Item::STORAGES.include?(@to) && @to != @item.storage

      thawed = @item.frozen_storage?
      was = [ @item.window_start, @item.window_end ]
      rewindow(storage: @to, acquired_on: thawed ? Date.current : @item.acquired_on,
               opened_on: @item.opened_on, thawed_on: (Date.current if thawed))
      @item.window_start = [ @item.window_start, was[0] ].min
      @item.window_end = [ @item.window_end, was[1] ].min
      @item.assign_attributes(storage: @to, storage_changed_at: Time.current)
    end

    # A "no" must not become a delete.
    def apply_snooze
      @item.snoozed_until = Date.current + snooze_days
    end

    def snooze_days = (@days || 3).to_i.clamp(1, 30)

    def rewindow(**inputs)
      window = Freshness::Estimator.call(category: @item.category, product: @item.product, **inputs)
      @item.assign_attributes(window_start: window.window_start, window_end: window.window_end,
                              confidence: window.confidence)
    end
  end
end
