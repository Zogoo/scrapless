module Text
  # Splits a typed or spoken line into the parts we already know and the parts we
  # do not. Only the second list costs money.
  #
  # For a household that shops the same way every week this converges on free:
  # "milk, bread, eggs" is three dictionary hits and zero model calls.
  #
  # The splitting itself is Text::Segmenter's, so a sentence with no commas
  # ("milch brot eier") is three parts here too, rather than one part that the
  # fuzzy lookup below would resolve to a single food.
  class Splitter < ApplicationService
    QUANTITY = /\A(\d+(?:[.,]\d+)?)\s*(kg|g|ml|l|x)?\s*(?:x\s*)?(.+)\z/i

    def initialize(text:, household: nil)
      @text = text.to_s
      @household = household
    end

    def call
      known = []
      unknown = []

      Segmenter.call(text: @text, household: @household).parts.each do |part|
        quantity, unit, name = decompose(part)
        entry = ProductAlias.lookup(name, household: @household)

        if entry
          known << { "raw_text" => part, "name" => entry.display_name, "quantity" => quantity,
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
