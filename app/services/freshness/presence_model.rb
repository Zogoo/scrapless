module Freshness
  # P(the food is still in the fridge).
  #
  # This is the correction two reviewers made to the original plan (doc 0): the
  # engine modelled spoilage only, so "consumption is inferred" was really a
  # timer, and it fired alerts exactly when food is most likely already eaten.
  #
  # A household that buys milk every four days is telling us, for free and in its
  # own capture history, how long milk lasts here. Where there is no history yet,
  # the category's consume_p50 is the cold start.
  #
  # The curve is a half-life: P = 0.5 at exactly the consumption cadence, with a
  # long tail because leftovers linger. An exponential rather than a cliff —
  # nobody finishes the spinach at noon on day five.
  class PresenceModel < ApplicationService
    MIN_INTERVALS = 2
    LN2 = Math.log(2)

    # ⚠️ Doc 3 R4b AC1 says "an alert never fires below P(still present) = 0.6".
    # That number was written against a presence curve the doc never specified,
    # and with this one it is unreachable: for every category in the seed table,
    # presence has fallen below 0.6 before spoilage has risen at all, so a 0.6
    # floor means the app never alerts about anything. 0.30 is where this curve
    # sits at doc 3 §3.4's own worked example — broccoli on day 8, the day that
    # document says should be at risk. The intent of AC1 is kept ("do not alert
    # about food that has probably been eaten"); the constant is recalibrated to
    # the curve underneath it, and that swap should be re-checked against the
    # Phase 0 diary study rather than trusted.
    ALERT_FLOOR = 0.30

    # Where we are genuinely unsure enough to spend one of the weekly sweep's
    # questions — and only once the food is old enough for the answer to matter.
    AMBIGUOUS_BAND = (0.25..0.6)

    def initialize(item:, on: Date.current, cadence: nil)
      @item = item
      @on = on
      @cadence = cadence
    end

    def call
      base = age_days <= 0 ? 1.0 : Math.exp(-LN2 * age_days / cadence_days.to_f)
      (base * partial_use_multiplier).clamp(0.01, 1.0).round(3)
    end

    private

    def age_days = (@on - @item.acquired_on).to_i

    # Each "I used half of it" halves what is left. Read off the append-only
    # event log rather than stored on the item, so the arithmetic stays visible.
    def partial_use_multiplier
      count = @item.item_events.where(kind: "partial_use").count
      count.zero? ? 1.0 : 0.5**count
    end

    def cadence_days
      @cadence_days ||= (@cadence || household_cadence || category_cadence).clamp(1, 365)
    end

    # Median gap between purchases of the same thing, from this household's own
    # captures. Two intervals is a thin signal, but it beats a global constant,
    # and it is the only personalisation that costs the user nothing to provide.
    def household_cadence
      dates = @item.household.items
                   .where(canonical_name: @item.canonical_name)
                   .where.not(id: @item.id)
                   .order(:acquired_on).pluck(:acquired_on).uniq
      return nil if dates.size < MIN_INTERVALS + 1

      gaps = dates.each_cons(2).map { |a, b| (b - a).to_i }.reject(&:zero?)
      return nil if gaps.size < MIN_INTERVALS

      median(gaps)
    end

    def category_cadence
      ShelfLifeRule.for(@item.category, @item.storage)&.consume_p50 ||
        Estimator::FALLBACK.fetch(@item.storage, Estimator::FALLBACK["fridge"])[:consume]
    end

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
    end
  end
end
