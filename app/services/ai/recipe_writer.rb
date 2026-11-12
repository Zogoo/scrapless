module Ai
  # "What can I make from this?" -> two or three short recipes.
  #
  # The model only ever sees the household's own list, and nothing it says is
  # trusted: Recipes::GroundInInventory re-binds every ingredient to a real item
  # afterwards. The prompt is the first fence, not the only one.
  class RecipeWriter < ApplicationService
    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[recipes],
      properties: {
        recipes: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[title minutes ingredients steps],
            properties: {
              title: { type: "string" },
              minutes: { type: %w[integer null] },
              ingredients: {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: %w[item_id name amount optional],
                  properties: {
                    item_id: { type: %w[integer null], description: "id from the list; null only for a staple" },
                    name: { type: "string", description: "copied exactly from the list" },
                    amount: { type: %w[string null], description: "e.g. '200 g', 'half', '2'" },
                    optional: { type: "boolean" }
                  }
                }
              },
              steps: { type: "array", items: { type: "string" } }
            }
          }
        }
      }
    }.freeze

    SYSTEM = <<~PROMPT.freeze
      You suggest simple, everyday home cooking for an app that helps households
      use up food before it goes off. You get a JSON list of EXACTLY the food in
      this kitchen, most urgent first.

      Rules:
      1. Suggest up to 3 short recipes, each with 2-5 steps.
      2. Every ingredient that is not optional must come from the list: set
         item_id to its id and copy its name exactly.
      3. Build each recipe around items marked "use_first" where you sensibly can.
      4. Invent nothing. The only things you may add that are not on the list are
         salt, pepper, oil and water - and only as optional, with item_id null.
      5. Every non-optional ingredient must be named in the steps and actually used.
      6. Never call food expired, off or bad, and never tell anyone off.
      7. Write titles and steps in %<language>s.
      8. If nothing sensible can be made, return an empty list rather than forcing it.
    PROMPT

    LANGUAGES = { en: "English", de: "German" }.freeze

    def initialize(pantry:, household: nil, locale: I18n.locale)
      @pantry = pantry
      @household = household
      @locale = locale
    end

    def call
      return { "recipes" => [] } if @pantry.empty?
      return Stub.recipe_result(@pantry) unless Config.live?

      Router.new(household: @household).json_completion(
        purpose: :recipe_suggest, schema: SCHEMA, max_output_tokens: 1500,
        messages: [
          { role: "system", content: format(SYSTEM, language: LANGUAGES.fetch(@locale.to_sym, "English")) },
          { role: "user", content: @pantry.to_json }
        ]
      )
    end
  end
end
