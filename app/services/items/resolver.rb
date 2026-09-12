module Items
  # Receipt jargon -> something a person recognises.
  #
  # The dictionary is consulted first and it is free. Every correction a user
  # makes feeds back into it, so the share of lines that need a model call falls
  # as the corpus grows — this is the asset the whole cost model rests on.
  class Resolver < ApplicationService
    Resolved = Struct.new(:display_name, :canonical_name, :category, :emoji, :storage, :source, keyword_init: true)

    EMOJI = {
      "produce" => "🥦", "dairy" => "🥛", "meat_fish" => "🍗", "bakery" => "🥖",
      "deli" => "🧀", "prepared" => "🍲", "frozen" => "🧊", "pantry" => "🥫",
      "drinks" => "🧃", "other" => "🍽️"
    }.freeze

    def initialize(raw_text:, name: nil, category: nil, merchant: nil, storage: nil)
      @raw_text = raw_text.to_s
      @name = name.presence
      @category = category.presence
      @merchant = merchant.presence
      @storage = storage.presence
    end

    def call
      from_dictionary || from_hints
    end

    private

    def from_dictionary
      entry = ProductAlias.lookup(@raw_text, merchant: @merchant)
      entry ||= ProductAlias.lookup(@name, merchant: @merchant) if @name
      return nil if entry.nil?

      build(display: entry.canonical_name.titleize, canonical: entry.canonical_name,
            category: entry.category, emoji: entry.emoji, source: "dictionary")
    end

    def from_hints
      display = @name.presence || tidy(@raw_text)
      category = Categories.valid?(@category) ? @category : Categories.guess("#{@name} #{@raw_text}")
      build(display: display, canonical: display.downcase, category: category, source: "heuristic")
    end

    def build(display:, canonical:, category:, source:, emoji: nil)
      category = Categories.coerce(category)
      Resolved.new(
        display_name: display, canonical_name: canonical, category: category,
        emoji: emoji.presence || EMOJI.fetch(category, "🍽️"),
        storage: @storage.presence || Categories.storage_for(category),
        source: source
      )
    end

    # "BABYSPINAT 260G" reads badly in a list; "Babyspinat 260G" reads fine.
    def tidy(text)
      cleaned = text.to_s.gsub(/[*#]/, " ").squeeze(" ").strip
      cleaned = cleaned.downcase.titleize if cleaned == cleaned.upcase
      cleaned.presence || "Item"
    end
  end
end
