module Recipes
  # "What can I make for this meal?", answered from what is actually in the kitchen,
  # with the food most at risk put first.
  #
  # Breakfast, lunch and dinner are each generated at most once a day for a
  # fridge. The answer is stored, so a second tap shows it again and does not
  # call the model, even after a restart or a change in the kitchen. Only an
  # answer with recipes is stored: an empty one was kept for the whole day, and
  # a full kitchen said "nothing to cook" at every breakfast tap after it. A fridge
  # still only gets a few real model calls an hour, counted out of the ai_calls
  # ledger, and the daily Ai::Budget still applies underneath, through the router.
  class Suggest < ApplicationService
    class TooMany < StandardError; end
    class UnknownMeal < StandardError; end
    class UnknownRefinement < StandardError; end

    # "Schneller", "Ohne Kochen", "Andere Zutaten" under a result: one new
    # answer with that extra rule, replacing the day's stored one.
    REFINEMENTS = {
      "quicker" => "Every recipe takes at most 15 minutes in total, preparation included.",
      "no_cooking" => "Nothing is cooked or heated: no stove, oven, microwave or toaster.",
      "different" => "Build the recipes around different items from the list than the last suggestions did."
    }.freeze

    MEALS = MealSuggestion::MEALS
    MAX_RECIPES = 3
    # A long list costs tokens and does not make better dinners; the most urgent
    # thirty is plenty to cook from.
    MAX_ITEMS = 30
    MAX_CALLS_PER_HOUR = 6

    # After this hour on a school day, the Brotbox to plan is tomorrow's.
    BROTBOX_CUTOFF_HOUR = 16

    # kitchen_empty tells "there is no food" apart from "nothing came of it".
    # for_date is the day the answer is for: today, except a Brotbox, which is
    # for the next school day.
    Result = Struct.new(:recipes, :cached, :meal, :kitchen_empty, :for_date, keyword_init: true)

    # The next school day, in the kitchen's own time zone: today if it is a
    # weekday before 16:00, otherwise the next Monday to Friday. Holidays and
    # Schulferien are not known yet.
    def self.school_day(household, now = Time.current)
      local = household.local_now(now)
      day = local.to_date
      return day if day.on_weekday? && local.hour < BROTBOX_CUTOFF_HOUR

      day += 1
      day += 1 until day.on_weekday?
      day
    end

    def initialize(household:, meal:, locale: I18n.locale, on: Date.current, refine: nil)
      @household = household
      @meal = meal.to_s.downcase
      @locale = locale
      @on = on
      @refine = refine.presence&.to_s
    end

    def call
      raise UnknownMeal, @meal unless MEALS.include?(@meal)
      # No Brotboxen, or never said: there is no Brotbox to plan.
      raise UnknownMeal, @meal if brotbox? && @household.brotbox_count.to_i.zero?
      raise UnknownRefinement, @refine if @refine && !REFINEMENTS.key?(@refine)

      @on = self.class.school_day(@household) if brotbox?
      result = answer
      result.for_date = @on
      result
    end

    private

    def brotbox? = @meal == "brotbox"

    def answer
      stored = remembered
      if stored && !@refine
        return Result.new(recipes: stored.payload, cached: true, meal: @meal, kitchen_empty: false)
      end
      return Result.new(recipes: [], cached: false, meal: @meal, kitchen_empty: true) if pantry.empty?

      recipes = write_recipes
      return Result.new(recipes: [], cached: false, meal: @meal, kitchen_empty: false) if recipes.empty?

      record = @refine ? replace(stored, recipes) : save(recipes)
      Result.new(recipes: record.payload, cached: !record.previously_new_record?, meal: @meal, kitchen_empty: false)
    end

    # A refined answer takes the place of the day's stored one; an empty one
    # (returned above) leaves what was there.
    def replace(stored, recipes)
      MealSuggestion.transaction do
        stored&.destroy!
        save(recipes)
      end
    end

    def remembered
      @household.meal_suggestions.find_by(meal: @meal, served_on: @on, locale: @locale.to_s)
    end

    # A second request that slipped in while this one was writing loses the
    # race and shows the row that won, rather than keeping a second answer.
    def save(recipes)
      MealSuggestion.create!(household: @household, meal: @meal, served_on: @on,
                             locale: @locale.to_s, body: recipes.to_json)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      remembered || raise
    end

    def write_recipes
      raise TooMany if Ai::Config.live? && calls_this_hour >= MAX_CALLS_PER_HOUR

      raw = Ai::RecipeWriter.call(pantry: pantry, meal: @meal, household: @household, locale: @locale,
                                  rules: FoodRules.call(household: @household) + refinement_rules,
                                  boxes: (@household.brotbox_count if brotbox?))
      written = Array(raw["recipes"])
      grounded(written).tap do |kept|
        # Which of the two it was, without what is in anyone's kitchen.
        if kept.empty?
          Rails.logger.info("recipes empty meal=#{@meal} pantry=#{pantry.size} written=#{written.size} kept=0")
        end
      end
    end

    def grounded(written)
      written
        .filter_map { |recipe| GroundInInventory.call(recipe: recipe, items: items, use_first_ids: use_first_ids,
                                              household: @household) }
        .uniq { |recipe| recipe[:title].downcase }
        .sort_by.with_index { |recipe, index| [ -recipe[:use_first_count], index ] }
        .first(MAX_RECIPES)
    end

    # The extra rule, and for "different" what the last answer was built on,
    # by name, so the model can avoid it.
    def refinement_rules
      return [] unless @refine

      rules = [ REFINEMENTS.fetch(@refine) ]
      used = Array(remembered&.payload).flat_map { |recipe| Array(recipe[:ingredients]) }
                                       .reject { |ingredient| ingredient[:optional] }
                                       .map { |ingredient| ingredient[:name] }.compact.uniq
      rules << "Already suggested, so leave these out where you can: #{used.to_json}." if @refine == "different" && used.any?
      rules
    end

    # "3 Stück", not "3 piece": the unit is a code from the readers' schema, and
    # the model copied it into the recipe as it was. Unknown units pass through.
    def amount(item)
      quantity = item.quantity&.to_f&.then { |q| q % 1 == 0 ? q.to_i : q }
      unit = item.unit.presence && I18n.t("units.#{item.unit}", count: quantity || 1, locale: @locale, default: item.unit)
      [ quantity, unit ].compact.join(" ").presence
    end

    def calls_this_hour
      AiCall.where(household: @household, purpose: "recipe_suggest", created_at: 1.hour.ago..).count
    end

    # Ghosts are left out: P(still present) is low enough that we have already
    # stopped showing them, and a recipe built on food that is gone is worse
    # than no recipe.
    def scored
      @scored ||= Freshness::RiskScorer.call(items: @household.items.active.by_urgency.to_a, on: @on)
                                       .reject { |s| s.phase == "ghost" }
                                       .first(MAX_ITEMS)
    end

    def items = scored.map(&:item)

    def use_first_ids
      @use_first_ids ||= scored.select(&:worth_showing?).map { |s| s.item.id }
    end

    # One entry per food, however many packs or names it came in under:
    # "Hähnchenbrustfilet" and "chicken breast" were offered as two
    # ingredients. The most urgent pack speaks for the product.
    def pantry
      @pantry ||= scored.uniq { |s| s.item.product_id || s.item.canonical_name.downcase }.map do |s|
        {
          id: s.item.id,
          name: Copy.bare_name(s.item).strip,
          amount: amount(s.item),
          storage: s.item.storage,
          priority: use_first_ids.include?(s.item.id) ? "use_first" : nil
        }.compact
      end
    end
  end
end
