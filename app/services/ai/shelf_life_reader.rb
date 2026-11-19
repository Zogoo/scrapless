module Ai
  # How long a food keeps, per place, asked once per product for every kitchen.
  #
  # The category table (db/seeds.rb) gives fresh milk, UHT milk, yoghurt and
  # Parmesan the same 8/14 days because they are all "dairy". This asks the
  # model for the food itself, the first time any kitchen meets it; the answer
  # is stored on the product (Products::LearnShelfLife) and every later pack, in
  # any kitchen, reads it for free.
  #
  # One batched text call for all the new products in a capture, on the text
  # tier: it is general knowledge, not reading, and it is paid once per food.
  class ShelfLifeReader < ApplicationService
    PLACE = {
      anyOf: [
        {
          type: "object",
          additionalProperties: false,
          required: %w[typical max opened],
          properties: {
            typical: { type: "integer", description: "days until most households would have used it, unopened" },
            max: { type: "integer", description: "the latest day it is still good if stored well, unopened" },
            opened: { type: %w[integer null], description: "days it keeps once opened; null if that does not apply" }
          }
        },
        { type: "null" }
      ]
    }.freeze

    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[products],
      properties: {
        products: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[product fridge freezer pantry],
            properties: { product: { type: "string" }, fridge: PLACE, freezer: PLACE, pantry: PLACE }
          }
        }
      }
    }.freeze

    SYSTEM = <<~PROMPT.freeze
      You give household shelf lives for foods, in whole days from the day of
      purchase, as a careful food-safety adviser would (BfR, Verbraucherzentrale,
      USDA FoodKeeper). Return one entry per product you are given, with the
      product exactly as given.

      For each place a household keeps food - fridge, freezer, pantry (a
      cupboard at room temperature) - give typical, max and opened days, or null
      if the food is not normally kept there or does not keep there (fresh milk
      in the pantry, lettuce in the freezer).

      - typical: when most households would have used it, unopened.
      - max: the latest it is still good if stored well, unopened. Not longer.
      - opened: how long it keeps once opened or cut; null if not applicable.
      - If a name covers several kinds ("cheese", "sausage"), answer for the
        most perishable common kind. Too short is a nuisance; too long makes
        someone ill.
      - Raw meat, fish, poultry and cooked dishes: be strict.
    PROMPT

    def initialize(products:, household: nil)
      @products = Array(products).map(&:to_s).compact_blank.uniq
      @household = household
    end

    # { "milk" => { "fridge" => {...} | nil, "freezer" => ..., "pantry" => ... } }
    def call
      return {} if @products.empty?

      result = Router.new(household: @household).json_completion(
        purpose: :shelf_life, schema: SCHEMA, max_output_tokens: 60 * @products.size + 200,
        timeout: 8,
        messages: [
          { role: "system", content: SYSTEM },
          { role: "user", content: @products.to_json }
        ]
      )

      Array(result["products"]).each_with_object({}) do |entry, answers|
        key = entry["product"].to_s
        next unless @products.include?(key)

        answers[key] = Product::PLACES.index_with { |place| entry[place] }
      end
    end
  end
end
