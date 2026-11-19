module Freshness
  # Turns "we think this is broccoli, bought Tuesday" into an uncertainty band
  # with an honest confidence attached.
  #
  # Layers, highest confidence first (doc 3 §3.4):
  #   1. a printed date read off the packet
  #   2. the product's own shelf life for the storage location, learned once
  #      from the model (Products::LearnShelfLife)
  #   3. a category rule for the storage location
  #   4. the global fallback for that storage location
  #
  # The result is a band [window_start, window_end] — "it goes off somewhere in
  # here" — never a single date. That is the schema enforcing a product promise:
  # with no `expires_on` column, the UI *cannot* render a precision we do not
  # have, which is the failure that made Fridgely notorious.
  #
  # Freezer is a lookup, never a multiplier: frozen chicken is nine months, not
  # eight times a two-day fridge window.
  class Estimator < ApplicationService
    FALLBACK = {
      "fridge" => { p50: 6, p90: 10, consume: 5 },
      "freezer" => { p50: 120, p90: 240, consume: 90 },
      "pantry" => { p50: 60, p90: 180, consume: 45 }
    }.freeze

    # Where the band opens, as a fraction of the median shelf life. Before this
    # point we claim nothing at all.
    BAND_OPENS_AT = 0.7

    # Days thawed food keeps in the fridge or cupboard. USDA FSIS, "The Big
    # Thaw": poultry, minced meat and fish an extra day or two after thawing in
    # the fridge, red-meat cuts 3-5 days. meat_fish holds all of them, so it
    # takes the short end. ⚠️ The default for everything else is our estimate.
    THAWED_DAYS = { "meat_fish" => 2 }.freeze
    THAWED_DEFAULT = 3

    # Days an opened pack keeps when the product says nothing (doc 5: a
    # per-storage remaining life, not a multiplier).
    OPENED_DEFAULT = { "freezer" => 2 }.freeze
    OPENED_FALLBACK = 3

    # How long an opened pack keeps, for Items::Resolve as well as here: the
    # product's own answer, but never longer than the default for high-risk food.
    def self.opened_days(category:, storage:, product: nil)
      default = OPENED_DEFAULT.fetch(storage.to_s, OPENED_FALLBACK)
      own = product&.shelf_life_for(storage)&.dig(:opened)
      return default if own.nil?

      Categories.high_risk?(category) ? [ own, default ].min : own
    end

    Result = Struct.new(:window_start, :window_end, :confidence, :consume_days, :high_risk, keyword_init: true)

    def initialize(category:, storage: "fridge", acquired_on: Date.current,
                   date_label_type: "none", date_label_value: nil, opened_on: nil, thawed_on: nil,
                   product: nil)
      @category = category.presence || "unknown"
      @product = product
      @storage = Item::STORAGES.include?(storage) ? storage : "fridge"
      @acquired_on = acquired_on || Date.current
      @date_label_type = date_label_type.presence || "none"
      @date_label_value = date_label_value
      @opened_on = opened_on
      @thawed_on = thawed_on
    end

    def call
      result = printed_date_window || product_window || category_window || fallback_window
      apply_opened!(result)
      apply_thawed!(result)
      clamp!(result)
      result
    end

    private

    def rule = @rule ||= ShelfLifeRule.for(@category, @storage)

    # A printed date is the only precision we ever have, so it wins outright.
    #
    # The German distinction is legally loaded and must never be blurred: a
    # Verbrauchsdatum is a safety date and is never extended; a
    # Mindesthaltbarkeitsdatum is a quality date and usually may be.
    def printed_date_window
      return nil if @date_label_value.blank? || @date_label_type == "none"

      if @date_label_type == "verbrauchsdatum"
        Result.new(window_start: @date_label_value - 1, window_end: @date_label_value,
                   confidence: 0.95, consume_days: consume_default, high_risk: true)
      else
        Result.new(window_start: @date_label_value - 2, window_end: @date_label_value + 3,
                   confidence: 0.9, consume_days: consume_default, high_risk: false)
      end
    end

    # The food's own numbers. The key can be coarser than the food, and the
    # answer came from a model, so high-risk food (meat, fish, deli, cooked
    # dishes outside the freezer) never gets longer than its category allows.
    def product_window
      life = @product&.shelf_life_for(@storage)
      return nil if life.nil?

      max = life[:max]
      max = [ max, category_max ].min if high_risk?
      band([ life[:typical], max ].min, max, confidence: 0.65, consume: consume_default, high_risk: high_risk?)
    end

    def high_risk? = rule&.high_risk || (Categories.high_risk?(@category) && @storage != "freezer")

    def category_max = rule&.days_p90 || FALLBACK.fetch(@storage)[:p90]

    def category_window
      return nil if rule.nil? || rule.category == "unknown"

      band(rule.days_p50, rule.days_p90, confidence: 0.6,
           consume: rule.consume_p50, high_risk: rule.high_risk)
    end

    def fallback_window
      f = FALLBACK.fetch(@storage)
      band(f[:p50], f[:p90], confidence: 0.3, consume: f[:consume], high_risk: false)
    end

    def band(p50, p90, confidence:, consume:, high_risk:)
      Result.new(
        window_start: @acquired_on + (p50 * BAND_OPENS_AT).round,
        window_end: @acquired_on + p90,
        confidence: confidence,
        consume_days: consume,
        high_risk: high_risk
      )
    end

    def consume_default
      rule&.consume_p50 || FALLBACK.fetch(@storage)[:consume]
    end

    # Opening restarts the clock on a shorter, per-storage remaining life rather
    # than scaling the original window by a constant — milk opened on day 5 of a
    # 10-day window is otherwise arithmetically undefined.
    def apply_opened!(result)
      return if @opened_on.blank?

      opened_life = self.class.opened_days(category: @category, storage: @storage, product: @product)
      result.window_end = [ result.window_end, @opened_on + opened_life ].min
      result.window_start = [ result.window_start, @opened_on ].min
      result.confidence = [ result.confidence, 0.7 ].min
    end

    # Out of the freezer is not "fresh from the shop": thawed chicken given a
    # fresh fridge window would read as fine for a week. Same shape as opening.
    def apply_thawed!(result)
      return if @thawed_on.blank?

      life = THAWED_DAYS.fetch(@category, THAWED_DEFAULT)
      result.window_end = [ result.window_end, @thawed_on + life ].min
      result.window_start = [ result.window_start, @thawed_on ].min
      result.confidence = [ result.confidence, 0.6 ].min
    end

    def clamp!(result)
      result.window_start = [ result.window_start, @acquired_on ].max
      result.window_end = [ result.window_end, result.window_start ].max
    end
  end
end
