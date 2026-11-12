require "digest"

module Recipes
  # "What can I make tonight?", answered from what is actually in the kitchen,
  # with the food most at risk put first.
  #
  # Three things keep this cheap. The answer is cached against a fingerprint of
  # the inventory, so tapping again costs nothing until the food changes. A
  # fridge gets a few real model calls an hour, counted out of the ai_calls
  # ledger (a cache counter would reset on restart). And the daily Ai::Budget
  # still applies underneath, through the router.
  class Suggest < ApplicationService
    class TooMany < StandardError; end

    MAX_RECIPES = 3
    # A long list costs tokens and does not make better dinners; the most urgent
    # thirty is plenty to cook from.
    MAX_ITEMS = 30
    MAX_CALLS_PER_HOUR = 6
    CACHE_TTL = 12.hours

    Result = Struct.new(:recipes, :cached, keyword_init: true)

    def initialize(household:, locale: I18n.locale, on: Date.current)
      @household = household
      @locale = locale
      @on = on
    end

    def call
      return Result.new(recipes: [], cached: false) if pantry.empty?

      cached = Rails.cache.read(cache_key)
      return Result.new(recipes: cached, cached: true) unless cached.nil?

      recipes = write_recipes
      Rails.cache.write(cache_key, recipes, expires_in: CACHE_TTL)
      Result.new(recipes: recipes, cached: false)
    end

    private

    def write_recipes
      raise TooMany if Ai::Config.live? && calls_this_hour >= MAX_CALLS_PER_HOUR

      raw = Ai::RecipeWriter.call(pantry: pantry, household: @household, locale: @locale)
      Array(raw["recipes"])
        .filter_map { |recipe| GroundInInventory.call(recipe: recipe, items: items, use_first_ids: use_first_ids) }
        .uniq { |recipe| recipe[:title].downcase }
        .sort_by.with_index { |recipe, index| [ -recipe[:use_first_count], index ] }
        .first(MAX_RECIPES)
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

    def pantry
      @pantry ||= scored.map do |s|
        {
          id: s.item.id,
          name: Copy.bare_name(s.item).strip,
          amount: [ s.item.quantity&.to_f&.then { |q| q % 1 == 0 ? q.to_i : q }, s.item.unit ].compact.join(" ").presence,
          storage: s.item.storage,
          priority: use_first_ids.include?(s.item.id) ? "use_first" : nil
        }.compact
      end
    end

    # The fingerprint is exactly what the model would be shown, plus the day and
    # language: same food, same answer; anything changes, ask again.
    def cache_key
      [ "recipes/v1", @household.id, @locale, @on.iso8601, Digest::SHA256.hexdigest(pantry.to_json) ].join("/")
    end
  end
end
