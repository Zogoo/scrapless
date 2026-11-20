module Products
  # Which product a model key belongs to once interchangeable varieties are
  # one food: "basmati rice" and "jasmine rice" are both "rice", so they share
  # one Kitchen line, one shelf life and one shopping suggestion.
  #
  # The list is a product decision, kept in config/product_merge.yml; its
  # header states the rule and the order of the checks. This class only
  # applies it. Pure: no database, and the same answer for the same input, so
  # merges can be recomputed (and split back apart) from items.source_product_key
  # by `rake products:recompute_merges`.
  #
  # Matching is on whole words. "pineapple" is not an apple and "watermelon"
  # is its own head, not a melon.
  class MergeKey
    CONFIG_PATH = Rails.root.join("config/product_merge.yml")

    Rules = Struct.new(:categories, :heads, :processing_words, :exceptions, keyword_init: true)

    def self.call(key:, category:, rules: self.rules)
      normalized = Product.normalize_key(key)
      return normalized if normalized.blank?
      return normalized unless rules.categories.include?(category.to_s)
      return normalized if rules.exceptions.include?(normalized)

      words = normalized.split
      return normalized if rules.processing_words.intersect?(words.to_set)

      head_for(words, rules) || normalized
    end

    # The title shown on a Kitchen line where varieties stack ("Reis"). Only
    # German is written down; any other language shows the pack's own name.
    def self.name_for(head, locale)
      return nil unless locale.to_s == "de"

      rules.heads[Product.normalize_key(head)]
    end

    # Longest head first, so "red bell pepper" is "bell pepper", not a pepper.
    def self.head_for(words, rules)
      rules.heads.keys.sort_by { |head| -head.split.size }.find do |head|
        head_words = head.split
        words.size >= head_words.size && words.last(head_words.size) == head_words
      end
    end

    def self.rules
      @rules ||= load_rules(YAML.safe_load_file(CONFIG_PATH))
    end

    # Exposed so a test can apply a changed copy of the file.
    def self.load_rules(config)
      normalize = ->(list) { Array(list).map { |entry| Product.normalize_key(entry) }.to_set }
      Rules.new(
        categories: Array(config["categories"]).map(&:to_s).to_set,
        heads: config.fetch("merge_heads", {}).to_h { |head, title| [ Product.normalize_key(head), title.to_s ] },
        processing_words: normalize.call(config["processing_words"]),
        exceptions: normalize.call(config["keep_exceptions"])
      )
    end

    def self.reset! = @rules = nil
  end
end
