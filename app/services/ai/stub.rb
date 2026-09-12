module Ai
  # Deterministic offline responses, used when no API key is configured.
  #
  # This is not a test mock — it is a product decision. The whole app has to be
  # clickable end to end with no key and no spend, or the UI cannot be built or
  # demonstrated without an invoice attached.
  module Stub
    module_function

    def image_result(hint: nil)
      return shelf_result if hint == "shelf_photo"

      {
        "kind" => "receipt",
        "merchant" => "REWE",
        "purchased_on" => Date.current.iso8601,
        "lines" => [
          line("BROKKOLI", "Broccoli", 1, "piece", 1.29, "A"),
          line("BABYSPINAT 260G", "Baby spinach", 260, "g", 1.99, "A"),
          line("H-MILCH 3,5%", "Milk", 1, "l", 1.09, "A"),
          line("HAEHNCHENSCHENKEL", "Chicken legs", 500, "g", 4.49, "A"),
          line("GOUDA AM STUECK", "Gouda", 200, "g", 2.79, "A"),
          line("WEIZENBROETCHEN 6ER", "Bread rolls", 6, "piece", 1.50, "A"),
          line("PFAND 0,25", "Deposit", 1, "piece", 0.25, "B", food: false)
        ],
        "totals" => { "sum" => 13.40 },
        "notes" => "stubbed response - no OPENAI_API_KEY configured"
      }
    end

    def shelf_result
      {
        "kind" => "food",
        "merchant" => nil,
        "purchased_on" => Date.current.iso8601,
        "lines" => [
          line("green broccoli crown", "Broccoli", 1, "piece", nil, nil),
          line("carton of milk", "Milk", 1, "l", nil, nil),
          line("bag of carrots", "Carrots", 500, "g", nil, nil)
        ],
        "totals" => { "sum" => nil },
        "notes" => "stubbed response - no OPENAI_API_KEY configured"
      }
    end

    # Splits on the separators people actually speak and type, so the stub still
    # reflects what the user typed rather than a canned list.
    def text_result(text)
      names = text.split(/,|\band\b|\bund\b|\n|;/i).map { |t| t.strip.squeeze(" ") }.reject(&:blank?)
      {
        "items" => names.first(20).map do |name|
          quantity, cleaned = extract_quantity(name)
          {
            "raw_text" => name, "name" => cleaned.capitalize, "quantity" => quantity,
            "unit" => nil, "category" => Categories.guess(cleaned), "storage" => Categories.storage_for(Categories.guess(cleaned))
          }
        end
      }
    end

    def transcript = "milk, broccoli and six eggs"

    def line(raw, name, quantity, unit, price, vat, food: true)
      { "raw_text" => raw, "name" => name, "quantity" => quantity, "unit" => unit,
        "price" => price, "vat_class" => vat, "food" => food }
    end

    def extract_quantity(text)
      match = text.match(/\A(\d+(?:[.,]\d+)?)\s*(?:x\s*)?(.+)\z/)
      return [ nil, text ] unless match

      [ match[1].tr(",", ".").to_f, match[2] ]
    end
  end
end
