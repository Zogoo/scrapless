module Text
  # Splits a typed or spoken line into the parts we already know and the parts we
  # do not. Only the second list costs money.
  #
  # For a household that shops the same way every week this converges on free:
  # "milk, bread, eggs" is three dictionary hits and zero model calls.
  class Splitter < ApplicationService
    SEPARATORS = /,|;|\n|\band\b|\bund\b|\bplus\b/i
    QUANTITY = /\A(\d+(?:[.,]\d+)?)\s*(kg|g|ml|l|x)?\s*(?:x\s*)?(.+)\z/i

    def initialize(text:)
      @text = text.to_s
    end

    def call
      known = []
      unknown = []

      @text.split(SEPARATORS).map { |part| part.strip.squeeze(" ") }.reject(&:blank?).each do |part|
        quantity, unit, name = decompose(part)
        entry = ProductAlias.lookup(name)

        if entry
          known << { "raw_text" => part, "name" => entry.canonical_name.titleize, "quantity" => quantity,
                     "unit" => unit, "category" => entry.category, "food" => true }
        else
          unknown << part
        end
      end

      [ known, unknown ]
    end

    private

    def decompose(part)
      match = part.match(QUANTITY)
      return [ nil, nil, part ] unless match

      [ match[1].tr(",", ".").to_f, match[2]&.downcase, match[3].strip ]
    end
  end
end
