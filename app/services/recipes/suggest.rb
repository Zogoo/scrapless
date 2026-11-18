module Recipes
  # "What can I make for this meal?", answered from what is actually in the kitchen,
  # with the food most at risk put first.
  #
  # Breakfast, lunch and dinner are each generated at most once a day for a
  # fridge. The answer is stored, so a second tap shows it again and does not
  # call the model, even after a restart or a change in the kitchen. A fridge
  # still only gets a few real model calls an hour, counted out of the ai_calls
  # ledger, and the daily Ai::Budget still applies underneath, through the router.
  class Suggest < ApplicationService
    class TooMany < StandardError; end
    class UnknownMeal < StandardError; end

    MEALS = MealSuggestion::MEALS
    MAX_RECIPES = 3
    # A long list costs tokens and does not make better dinners; the most urgent
    # thirty is plenty to cook from.
    MAX_ITEMS = 30
    MAX_CALLS_PER_HOUR = 6

    Result = Struct.new(:recipes, :cached, :meal, keyword_init: true)

    def initialize(household:, meal:, locale: I18n.locale, on: Date.current)
      @household = household
      @meal = meal.to_s.downcase
      @locale = locale
      @on = on
    end

    def call
      raise UnknownMeal, @meal unless MEALS.include?(@meal)

      stored = remembered
      return Result.new(recipes: stored.payload, cached: true, meal: @meal) if stored
      return Result.new(recipes: [], cached: false, meal: @meal) if pantry.empty?

      record = save(write_recipes)
      Result.new(recipes: record.payload, cached: !record.previously_new_record?, meal: @meal)
    end

    private

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

      raw = Ai::RecipeWriter.call(pantry: pantry, meal: @meal, household: @household, locale: @locale)
      Array(raw["recipes"])
        .filter_map { |recipe| GroundInInventory.call(recipe: recipe, items: items, use_first_ids: use_first_ids,
                                              household: @household) }
        .uniq { |recipe| recipe[:title].downcase }
        .sort_by.with_index { |recipe, index| [ -recipe[:use_first_count], index ] }
        .first(MAX_RECIPES)
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
