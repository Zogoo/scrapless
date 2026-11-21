module Recipes
  # What a household said about how it eats, as hard rules for the recipe model
  # (Settings → Essen). Applies to every meal.
  #
  # The quick choices are stored as fixed words ("Schwein", whatever the phone's
  # language) and each has a written-out rule, because "no pork" alone lets
  # bacon and gelatine through. Anything typed by the household goes in as a
  # quoted JSON string: it names a food, and must never read as an instruction.
  #
  # Not medical. These are foods to leave out, and the screen asks people to
  # check the ingredients themselves.
  class FoodRules < ApplicationService
    DIETS = {
      "vegetarian" => "Vegetarian: never use meat, poultry, fish or seafood, or anything made from them " \
                      "(gelatine, meat or fish stock, fish sauce, lard).",
      "vegan" => "Vegan: never use meat, poultry, fish, seafood, eggs, milk, butter, cheese, yoghurt, cream, " \
                 "honey, or anything made from them (gelatine, stock, whey)."
    }.freeze

    EXCLUSIONS = {
      "schwein" => "Never use pork or pork products (bacon, ham, salami, sausages with pork, lard, gelatine).",
      "nüsse" => "Never use nuts or anything made from them (almonds, hazelnuts, walnuts, cashews, peanuts, " \
                 "nut butters, nut oils, marzipan, nougat).",
      "fisch" => "Never use fish or seafood, or anything made from them (fish sauce, anchovies, shrimp, tuna).",
      "laktose" => "Never use dairy that contains lactose (milk, cream, cheese, yoghurt, butter, quark) " \
                   "unless the item is named lactose-free.",
      "gluten" => "Never use wheat, rye, barley or spelt, or anything made from them (bread, pasta, flour, " \
                  "couscous, beer), unless the item is named gluten-free."
    }.freeze

    def initialize(household:)
      @household = household
    end

    # English sentences, one per rule; empty when nothing was said.
    def call
      rules = []
      rules << DIETS[@household.diet] if DIETS.key?(@household.diet)
      Array(@household.excluded_foods).each do |food|
        rules << (EXCLUSIONS[food.to_s.downcase] || "Never use this food or anything made from it: #{food.to_s.to_json}.")
      end
      rules
    end
  end
end
