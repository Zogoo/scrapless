module Ai
  # Classifies the photo and extracts it in the same call.
  #
  # One call, not two. A separate "is this a receipt?" round trip would double
  # the per-capture cost to answer a question the extraction step already has to
  # answer to do its job.
  class ImageReader < ApplicationService
    # What each returned row is. Only "food" becomes an item.
    #
    # A required label, not a yes/no: asked for "one entry per printed line",
    # the model also returned the rows a till prints *under* a product — a count
    # ("2 Stk x 0,79"), a weight, a multi-buy saving — and, having no product
    # name for them, made one up: "(bundle)", "(item line repeated)". Those were
    # flagged food and landed in the kitchen for six months. Making every row
    # say what it is lets those be dropped by kind, on any till's layout,
    # without a list of phrases to keep up to date.
    ROWS = %w[food not_food detail discount deposit].freeze

    # What the whole photo is. A "bill" is a meal eaten out: nothing on it is
    # in the kitchen. Asked per row ("every dish on a restaurant bill is
    # not_food") the model never applied it — 3 of 3 runs put the steak and the
    # wine in the fridge — because it is a judgement about the document, not
    # about any one line. Captures::Ingest keeps nothing from a bill.
    #
    # The classification is fragile: any instruction that names "receipt" has
    # to name "bill" too. "On a receipt, box is null" alone turned the test
    # bill back into a receipt in 2 of 2 runs; "a receipt or a bill", 3 of 3 bill.
    KINDS = %w[receipt bill food unclear].freeze

    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[kind seen_inside merchant purchased_on lines totals notes],
      properties: {
        kind: { type: "string", enum: KINDS },
        seen_inside: { type: %w[string null], enum: [ "fridge", "freezer", nil ],
                       description: "only when the photo was taken inside a fridge or a freezer" },
        merchant: { type: %w[string null] },
        purchased_on: { type: %w[string null], description: "ISO 8601 date" },
        lines: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[raw_text name product quantity unit price vat_class row category storage box],
            properties: {
              raw_text: { type: "string", description: "verbatim, exactly as printed" },
              name: { type: "string", description: "what a shopper calls it, in the language the instructions name" },
              product: { type: "string", description: "always English, translated if need be: the food's generic name, lowercase, singular" },
              quantity: { type: %w[number null] },
              unit: { type: %w[string null], description: "g, kg, ml, l, piece" },
              price: { type: %w[number null] },
              vat_class: { type: %w[string null], enum: [ "A", "B", nil ] },
              row: { type: "string", enum: ROWS },
              category: { type: "string", enum: Categories::NAMES },
              storage: { type: "string", enum: Item::STORAGES },
              box: {
                anyOf: [
                  {
                    type: "object",
                    additionalProperties: false,
                    required: %w[x y w h],
                    description: "where the product is in the photo, as fractions of its width and height",
                    properties: {
                      x: { type: "number", description: "left edge, 0-1" },
                      y: { type: "number", description: "top edge, 0-1" },
                      w: { type: "number", description: "width, 0-1" },
                      h: { type: "number", description: "height, 0-1" }
                    }
                  },
                  { type: "null" }
                ]
              }
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
        "receipt" - a shop's till receipt / Kassenbon: food bought to take home
        "bill"    - a restaurant, cafe, bar or takeaway bill: food and drink
                    that was eaten or drunk there, with a table number, a
                    service charge or dishes rather than groceries
        "food"    - groceries, a fridge shelf, a worktop of shopping
        "unclear" - anything else, or too blurred to read

      Every entry is one product bought, never one printed row. Tills print
      rows under a product that only add to it: a count ("2 Stk x 0,79"), a
      weight ("1,080 kg x 1,50 EUR/kg"), a repeat, a multi-buy or bundle saving.
      Put a count or weight into that product's quantity and unit, and return
      the row itself only with row="detail", or not at all.

      row says what an entry is:
        "food"     - something to eat or drink, kept at home
        "not_food" - anything else sold: bags, household goods
        "detail"   - a count, weight, repeat or other row belonging to a product
        "discount" - a saving, coupon or bundle price
        "deposit"  - Pfand or Leergut
      On German receipts VAT class A (7%%) is almost always food and B (19%%)
      usually is not, but the item name wins over the VAT class.

      For a receipt: raw_text is the product's text as printed, abbreviations
      and typos included, but not the price, the VAT letter or a count or
      weight printed on a row of its own.
      For a photo of food: one entry per distinct product you can actually see;
      put a short description in raw_text and leave price null. Do not guess at
      items hidden behind other items. Give each entry a box: where it is in
      the photo, as fractions of the image (x, y = top-left corner, w, h =
      size, all 0-1), tight around the product. On a receipt or a bill, box is null.

      name is what a shopper calls the food, written in %<language>s whatever
      language the receipt or packet is in: abbreviations spelled out, a capital
      first letter, and the food only, without price, VAT letter, size, fat
      content, packaging ("bottle", "carton") or offer ("3+1 gratis").
      %<product>s
      category is the closest of these:
      %<categories>s
      storage is where this product is normally kept at home: chilled products
      in the fridge, frozen ones in the freezer, shelf-stable ones in the
      pantry. In a photo taken inside a fridge or freezer, that is where it is.
      seen_inside is "fridge" or "freezer" only when the photo was taken inside
      one; shopping on a worktop, a bag or a receipt is null.

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
          { role: "system", content: format(SYSTEM, language: Language.name, categories: Categories.prompt_guide,
                                            product: Product::PROMPT_RULE) },
          { role: "user", content: [
            { type: "text", text: "Read this photo. Write every name in #{Language.name}." },
            { type: "image_url", image_url: { url: data_url, detail: "high" } }
          ] }
        ]
      )
    end

    private

    def data_url = "data:#{@content_type};base64,#{Base64.strict_encode64(@image_data)}"
  end
end
