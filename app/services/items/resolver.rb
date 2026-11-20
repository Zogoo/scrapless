module Items
  # Receipt jargon -> something a person recognises.
  #
  # The dictionary is consulted first and it is free. Every correction a user
  # makes feeds back into it, so the share of lines that need a model call falls
  # as the corpus grows — this is the asset the whole cost model rests on.
  class Resolver < ApplicationService
    Resolved = Struct.new(:display_name, :canonical_name, :category, :emoji, :storage, :source, :product,
                          :source_product_key, keyword_init: true)

    EMOJI = {
      "produce" => "🥦", "dairy" => "🥛", "meat_fish" => "🍗", "bakery" => "🥖",
      "deli" => "🧀", "prepared" => "🍲", "frozen" => "🧊", "pantry" => "🥫",
      "drinks" => "🧃", "other" => "🍽️"
    }.freeze

    # `seen_storage`: the line's storage was seen, not guessed — a photo taken
    # inside the fridge or freezer. Only then does it beat a place this kitchen
    # taught by moving the food.
    def initialize(raw_text:, name: nil, category: nil, merchant: nil, storage: nil, household: nil, product: nil,
                   seen_storage: false)
      @raw_text = raw_text.to_s
      @name = name.presence
      @category = category.presence
      @merchant = merchant.presence
      @storage = storage.presence
      @seen_storage = seen_storage
      @household = household
      @product = product
    end

    def call
      from_dictionary || from_hints
    end

    private

    # A fuzzy match is a guess, and it may only fill a gap. When the model has
    # already named and placed the food, a near-miss must not overrule it:
    # "HAEHN.BRUSTFILET" became chicken thighs, and a photo's "bag baby
    # carrots" became Babyspinat, from a shared four-letter prefix. An exact
    # match — including the kitchen's own corrections — still wins.
    def from_dictionary
      entry = ProductAlias.lookup([ @raw_text, @name ], merchant: @merchant, household: @household,
                                                        fuzzy: !Categories.valid?(@category))
      return nil if entry.nil?

      # The dictionary says what the food is; the name shown is the model's
      # when it gave one, so it is in the person's language. With no model
      # answer (a typed word the dictionary knew) the dictionary's name stands.
      display = @name.present? && Categories.valid?(@category) ? tidy(@name) : entry.display_name
      build(display: display, canonical: display.downcase,
            category: entry.category, emoji: entry.emoji, source: "dictionary", storage: entry.storage,
            taught_place: taught_place(entry),
            product_key: entry.source_product_key.presence || entry.product&.key || @product)
    end

    def from_hints
      display = tidy(@name.presence || @raw_text)
      category = Categories.valid?(@category) ? @category : Categories.guess("#{@name} #{@raw_text}")
      build(display: display, canonical: display.downcase, category: category, source: "heuristic",
            product_key: @product)
    end

    # Where it is: what this line says (a photo shows the fridge), else what
    # the dictionary learned, else where its category usually lives.
    # A place this kitchen chose by moving the food (ProductAlias.remember_place!).
    def taught_place(entry)
      entry.storage if entry.household_id.present? && entry.source == "correction"
    end

    # The product is worked out here, once the category is final, so a
    # dictionary hit and a model answer merge the same way ("Babyspinat" from
    # the seeds and "baby spinach" from a photo are both spinach). The key
    # before merging is kept for the item (source_product_key).
    def build(display:, canonical:, category:, source:, emoji: nil, product_key: nil, storage: nil,
              taught_place: nil)
      category = Categories.coerce(category)
      source_key = Product.normalize_key(product_key).presence
      Resolved.new(
        display_name: display, canonical_name: canonical, category: category,
        emoji: emoji.presence || EMOJI.fetch(category, "🍽️"),
        storage: place(storage, taught_place, category),
        source: source, product: Product.for(source_key, category: category), source_product_key: source_key
      )
    end

    # Seen beats taught beats guessed: a photo inside the freezer, then where
    # this kitchen keeps it, then what the model or the dictionary assumed, then
    # where the category usually lives.
    def place(dictionary_storage, taught, category)
      return @storage if @seen_storage && @storage

      taught.presence || @storage || dictionary_storage.presence || Categories.storage_for(category)
    end

    # "BABYSPINAT 260G" reads badly in a list; "Babyspinat 260G" reads fine.
    # A capital first letter whatever the model sent ("chicken breast" came
    # back lowercase in about half the runs).
    def tidy(text)
      cleaned = text.to_s.gsub(/[*#]/, " ").squeeze(" ").strip
      cleaned = cleaned.downcase.titleize if cleaned == cleaned.upcase
      cleaned.upcase_first.presence || "Item"
    end
  end
end
