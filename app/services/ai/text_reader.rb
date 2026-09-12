module Ai
  # "milk, broccoli and two chicken breasts" -> rows.
  #
  # Only reached for text the alias dictionary could not resolve for free, which
  # is why it runs on the nano tier: by the time a token gets here it is a word
  # we have never seen, not a parsing problem.
  class TextReader < ApplicationService
    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[items],
      properties: {
        items: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[raw_text name quantity unit category storage],
            properties: {
              raw_text: { type: "string" },
              name: { type: "string" },
              quantity: { type: %w[number null] },
              unit: { type: %w[string null] },
              category: { type: "string", enum: Categories::NAMES },
              storage: { type: "string", enum: %w[fridge freezer pantry] }
            }
          }
        }
      }
    }.freeze

    SYSTEM = <<~PROMPT.freeze
      Turn a spoken or typed shopping sentence into structured food items.

      Rules:
      - One entry per distinct food. "two chicken breasts" is one entry, quantity 2.
      - name is plain language in the input's own language.
      - category must be one of the allowed values; use "other" when unsure.
      - storage is where a normal household would put it once home.
      - Ignore words that are not food ("I bought", "and", "also").
      - Return an empty list rather than guessing at an unintelligible input.
    PROMPT

    def initialize(text:, household: nil)
      @text = text.to_s.strip
      @household = household
    end

    def call
      return { "items" => [] } if @text.blank?
      return Stub.text_result(@text) unless Config.live?

      Router.new(household: @household).json_completion(
        purpose: :text_parse, schema: SCHEMA, max_output_tokens: 1200,
        messages: [
          { role: "system", content: SYSTEM },
          { role: "user", content: @text }
        ]
      )
    end
  end
end
