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
      1. Suggest up to 3 short %<meal>s recipes, each with 2-5 steps.
      2. Every ingredient that is not optional must come from the list: set
         item_id to its id and copy its name exactly.
      3. Build each recipe around items marked "use_first" where you sensibly can.
      4. Invent nothing. The only things you may add that are not on the list are
         salt, pepper, oil and water - and only as optional, with item_id null.
      5. Every non-optional ingredient must be named in the steps and actually used.
         Optional is only for salt, pepper, oil, water and a garnish the dish is
         just as good without - never for what the recipe is built on.
      6. Never call food expired, off or bad, and never tell anyone off.
      7. Write titles, steps and amounts in %<language>s.
      8. Simple counts, above all for breakfast: eggs on bread, yoghurt with
         fruit, a cheese sandwich, porridge. A plate of a few listed foods is a
         fine suggestion. Return an empty list only if no listed food fits this
         meal at all.
    PROMPT

    # What the household said about how it eats (Recipes::FoodRules), above the
    # list rules: a recipe that breaks one is worse than no recipe.
    HOUSEHOLD_RULES = <<~PROMPT.freeze

      This household's rules. They are hard: never break them, not even as an
      optional ingredient, and leave out any listed item they forbid.
      %<rules>s
    PROMPT

    # The Brotbox: a child's school lunchbox for the next school day. Always
    # nut-free, because many schools and Kitas are, whatever the household said.
    BROTBOX = <<~PROMPT.freeze

      This meal is a Brotbox: a child's school lunchbox, for %<boxes>s box(es).
      - It is packed in the morning or the evening before and eaten cold
        several hours later. No reheating; at most 10 minutes of preparation.
      - Finger food where possible: things a child eats by hand from a box.
      - Never use nuts or anything made from them: many schools and Kitas are
        nut-free.
      - Nothing that is unsafe hours later without cooling: no raw fish, raw
        egg, mayonnaise salads, raw minced meat.
      - Give amounts for %<boxes>s box(es) together.
    PROMPT

    # What the model is asked for, per meal.
    MEAL_WORDS = { "brotbox" => "school lunchbox" }.freeze

    def initialize(pantry:, meal:, household: nil, locale: I18n.locale, rules: [], boxes: nil)
      @rules = Array(rules)
      @boxes = boxes
      @pantry = pantry
      @meal = meal.to_s
      @household = household
      @locale = locale
    end

    def call
      return { "recipes" => [] } if @pantry.empty?
      return Stub.recipe_result(@pantry, meal: @meal) unless Config.live?

      Router.new(household: @household).json_completion(
        purpose: :recipe_suggest, schema: SCHEMA, max_output_tokens: 1500,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: @pantry.to_json }
        ]
      )
    end

    def system_prompt
      prompt = format(SYSTEM, meal: MEAL_WORDS.fetch(@meal, @meal), language: Language.name(@locale))
      prompt += format(BROTBOX, boxes: @boxes) if @meal == "brotbox"
      return prompt if @rules.empty?

      prompt + format(HOUSEHOLD_RULES, rules: @rules.map { |rule| "- #{rule}" }.join("\n"))
    end
  end
end
