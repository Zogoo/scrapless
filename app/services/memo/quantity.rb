module Memo
  # "2 Gurken", "2x Gurken", "2× Gurken", "zwei Gurken" -> [2, "Gurken"].
  #
  # Only a count of things becomes a quantity. A measure stays part of the
  # name ("500 g Mehl"), and so does a fraction ("0,5 Brot"): "500× Mehl" or
  # a rounded "1× Brot" would say something nobody asked for. Without a number
  # the quantity is nil, which tells a duplicate apart from "one more".
  module Quantity
    MAX = 99
    WORDS = {
      "ein" => 1, "eine" => 1, "einen" => 1, "eins" => 1, "zwei" => 2, "drei" => 3, "vier" => 4,
      "fünf" => 5, "fuenf" => 5, "sechs" => 6, "sieben" => 7, "acht" => 8, "neun" => 9, "zehn" => 10,
      "elf" => 11, "zwölf" => 12, "zwoelf" => 12,
      "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5, "six" => 6, "seven" => 7,
      "eight" => 8, "nine" => 9, "ten" => 10, "eleven" => 11, "twelve" => 12
    }.freeze
    # Measures: the number belongs to the amount, not to how many.
    MEASURES = %w[g gr gramm kg kilo ml cl dl l liter litre % mg].freeze

    module_function

    # [quantity or nil, name without the count]
    def parse(text)
      text = text.to_s.strip.squeeze(" ")
      match = text.match(/\A(\d{1,2})\s*(?:x|×)?\s+(.+)\z/i) || text.match(/\A(\d{1,2})(?:x|×)\s*(.+)\z/i)
      return counted(match[1].to_i, match[2], text) if match

      first, rest = text.split(" ", 2)
      count = WORDS[first.to_s.downcase]
      count && rest.present? ? counted(count, rest, text) : [ nil, text ]
    end

    def counted(count, rest, text)
      return [ nil, text ] if count < 1 || MEASURES.include?(rest.split.first.to_s.downcase)

      [ [ count, MAX ].min, rest.strip ]
    end
  end
end
