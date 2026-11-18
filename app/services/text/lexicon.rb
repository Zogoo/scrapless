module Text
  # Everything the dictation splitter can recognise, for one kitchen.
  #
  # Two layers, like ProductAlias:
  # - shared: the seeded dictionary, the suggester's staples and every
  #   language's spoken phrases (config/dictation). Built once per process and
  #   rebuilt only when the shared dictionary changes, so a dictionary of
  #   thousands of rows costs one cheap version query per request, not a load;
  # - this kitchen: its own aliases, what it has bought, what it has typed onto
  #   the list, and what it has taught the mic by correcting it
  #   (VocabularyEntry). Bounded by RECENT rows per source.
  class Lexicon
    RECENT = 500

    attr_reader :items, :leading, :trailing, :modifiers, :units, :numbers, :separators

    class << self
      def for(household) = new(shared: shared, household: household)

      def shared
        version = ProductAlias.shared.pick(Arel.sql("COUNT(*), MAX(updated_at)"))
        @shared = nil if @shared_version != version
        @shared_version = version
        @shared ||= build_shared
      end

      def reset! = (@shared = @shared_version = nil)

      def keys(words) = words.filter_map { |w| ProductAlias.normalize_key(w).presence }.to_set

      # How many words the longest phrase has, so matching tries no further
      # than the data needs, rather than up to a fixed constant.
      def longest_in(phrases) = phrases.map { |phrase| phrase.count(" ") + 1 }.max || 1

      private

      def build_shared
        phrases = Dictation::Vocabulary.combined
        words = ProductAlias.shared.pluck(:raw_text, :canonical_name).flatten
        words += Memo::Suggester::STAPLES.flat_map { |label, _category, word| [ label, word ] }
        items = keys(words)
        phrases.merge(items: items, items_longest: longest_in(items)).freeze
      end
    end

    def initialize(shared:, household:)
      learned = household ? household.vocabulary_entries.pluck(:kind, :phrase).group_by(&:first) : {}
      learned = learned.transform_values { |rows| rows.map(&:last) }

      own = self.class.keys(household_items(household)) | learned.fetch("item", [])
      @items = shared[:items] | own
      @items_longest = [ shared[:items_longest], self.class.longest_in(own) ].max
      @leading = shared[:leading] | learned.fetch("leading", [])
      @trailing = shared[:trailing] | learned.fetch("trailing", [])
      @modifiers = shared[:modifiers]
      @units = shared[:units]
      @numbers = shared[:numbers]
      @separators = shared[:separators]
    end

    attr_reader :items_longest

    def leading_longest = @leading_longest ||= self.class.longest_in(leading)
    def trailing_longest = @trailing_longest ||= self.class.longest_in(trailing)
    def numbers_longest = @numbers_longest ||= self.class.longest_in(numbers.keys)
    def modifiers_longest = @modifiers_longest ||= self.class.longest_in(modifiers)

    private

    # Only what a person entered: lines the splitter itself produced are not
    # evidence of anything, and learning them would repeat its mistakes.
    def household_items(household)
      return [] unless household

      household.product_aliases.pluck(:raw_text, :canonical_name).flatten +
        household.items.order(id: :desc).limit(RECENT).pluck(:canonical_name) +
        household.memo_items.where(source: %w[text suggestion]).order(id: :desc).limit(RECENT).pluck(:canonical_name)
    end
  end
end
