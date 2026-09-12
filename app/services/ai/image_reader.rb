module Ai
  # Classifies the photo and extracts it in the same call.
  #
  # One call, not two. A separate "is this a receipt?" round trip would double
  # the per-capture cost to answer a question the extraction step already has to
  # answer to do its job.
  class ImageReader < ApplicationService
    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[kind merchant purchased_on lines totals notes],
      properties: {
        kind: { type: "string", enum: %w[receipt food unclear] },
        merchant: { type: %w[string null] },
        purchased_on: { type: %w[string null], description: "ISO 8601 date" },
        lines: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[raw_text name quantity unit price vat_class food],
            properties: {
              raw_text: { type: "string", description: "verbatim, exactly as printed" },
              name: { type: "string", description: "plain language, in the receipt's language" },
              quantity: { type: %w[number null] },
              unit: { type: %w[string null], description: "g, kg, ml, l, piece" },
              price: { type: %w[number null] },
              vat_class: { type: %w[string null], enum: [ "A", "B", nil ] },
              food: { type: "boolean" }
            }
          }
        },
        totals: {
          type: "object",
          additionalProperties: false,
          required: %w[sum],
          properties: { sum: { type: %w[number null] } }
        },
        notes: { type: %w[string null] }
      }
    }.freeze

    SYSTEM = <<~PROMPT.freeze
      You read photographs taken in a kitchen and return structured JSON.

      First decide what the photo shows:
        "receipt" - a till receipt / Kassenbon / invoice
        "food"    - groceries, a fridge shelf, a worktop of shopping
        "unclear" - anything else, or too blurred to read

      For a receipt: return one entry per printed line item, with raw_text copied
      verbatim including abbreviations and typos. Set food=false for deposits
      (Pfand), bags, discounts and non-grocery goods; on German receipts VAT class
      A (7%) is almost always food and B (19%) usually is not, but the item name
      wins over the VAT class when they disagree.

      For food: return one entry per distinct product you can actually see. Put a
      short description in raw_text and a plain name in name. Leave price null.
      Do not guess at items hidden behind other items.

      Never invent a line. If a line is unreadable, omit it and say so in notes.
      An omission is recoverable; an invented item is not, because it reads as
      correct and the user will not catch it.
    PROMPT

    def initialize(image_data:, content_type:, household: nil, hint: nil)
      @image_data = image_data
      @content_type = content_type.presence || "image/jpeg"
      @household = household
      @hint = hint
    end

    def call
      return Stub.image_result(hint: @hint) unless Config.live?

      purpose = @hint == "shelf_photo" ? :shelf_photo_extract : :receipt_extract
      Router.new(household: @household).json_completion(
        purpose: purpose, schema: SCHEMA, max_output_tokens: 3000,
        messages: [
          { role: "system", content: SYSTEM },
          { role: "user", content: [
            { type: "text", text: "Read this photo." },
            { type: "image_url", image_url: { url: data_url, detail: "high" } }
          ] }
        ]
      )
    end

    private

    def data_url = "data:#{@content_type};base64,#{Base64.strict_encode64(@image_data)}"
  end
end
