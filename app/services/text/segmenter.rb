module Text
  # One spoken or typed sentence -> the list lines in it, in German or English,
  # with no punctuation needed and no model call.
  #
  # Browser recognisers return "I want to buy bread milk eggs" with no commas
  # (doc 15 §15.2.3), so splitting on punctuation alone made that one line. This
  # splits on what we already know instead: separators first, then filler
  # phrases off both ends, then the longest phrase the kitchen's dictionary
  # knows. Both languages are always tried, because a Berlin list is often
  # mixed ("Milch, toilet paper").
  #
  # Words it does not know survive as their own line ("toilet paper",
  # "something for Sunday") — a memo line does not have to be a known food.
  class Segmenter < ApplicationService
    Result = Struct.new(:parts, :unresolved, keyword_init: true)

    # A full stop splits, a decimal point does not ("1.5 kg").
    SEPARATORS = /[,;\n]|\.(?!\d)|\b(?:and|und|plus|also|sowie|dann|then)\b/i
    MAX_PARTS = 25
    MAX_PHRASE_TOKENS = 3
    # An unknown run this short, right before a known word, is read as part of
    # it: "oat milk", "peanut butter", "Bio Milch". A longer run is its own line.
    MAX_PREFIX_TOKENS = 2

    # Written as they are typed; compared after ProductAlias.normalize_key, so
    # "we're" and "we re" are the same phrase.
    LEADING = [
      # English
      "i want to buy", "i want to get", "i want", "i need to buy", "i need to get", "i need",
      "we need to buy", "we need to get", "we need", "we're out of", "we are out of",
      "i'd like", "i would like", "can you add", "could you add", "please add", "add",
      "put", "buy", "get", "grab", "pick up", "and", "also", "please", "some", "more",
      "a", "an", "the",
      # German
      "ich brauche", "ich brauch", "wir brauchen", "ich möchte", "ich will", "ich hätte gern",
      "ich hätte gerne", "wir haben kein", "wir haben keine", "wir haben keinen", "uns fehlt",
      "uns fehlen", "füge", "kauf", "kaufe", "hol", "hole", "besorg", "besorge", "bitte",
      "noch", "auch", "und", "etwas", "ein bisschen", "ein", "eine", "einen", "der", "die",
      "das", "den"
    ].freeze

    TRAILING = [
      "please", "too", "as well", "to the list",
      "kaufen", "holen", "besorgen", "bitte", "hinzufügen", "hinzu", "auch", "noch",
      "auf die liste"
    ].freeze

    NUMBERS = {
      "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5, "six" => 6, "seven" => 7,
      "eight" => 8, "nine" => 9, "ten" => 10, "eleven" => 11, "twelve" => 12, "dozen" => 12,
      "zwei" => 2, "drei" => 3, "vier" => 4, "fünf" => 5, "sechs" => 6, "sieben" => 7, "acht" => 8,
      "neun" => 9, "zehn" => 10, "elf" => 11, "zwölf" => 12, "dutzend" => 12
    }.freeze

    # Units are not counted against MAX_PREFIX_TOKENS: "2 kg Äpfel" is one line.
    UNITS = %w[
      x kg g ml l pack packs bag bags bottle bottles can cans loaf loaves box boxes
      stück packung packungen flasche flaschen dose dosen beutel tüte tüten glas gläser
    ].freeze

    def initialize(text:, household: nil)
      @text = text.to_s
      @household = household
    end

    def call
      parts = []
      unresolved = []

      @text.split(SEPARATORS).each do |chunk|
        tokens = trim(tokenize(chunk))
        next if tokens.empty?

        pieces, matched = segment(tokens)
        unresolved << join(tokens) if !matched && tokens.size >= 4
        parts.concat(pieces)
      end

      Result.new(parts: parts.first(MAX_PARTS), unresolved: unresolved)
    end

    private

    Token = Struct.new(:surface, :key)

    def tokenize(chunk)
      chunk.split(/\s+/).filter_map do |raw|
        key = ProductAlias.normalize_key(raw)
        next if key.blank?

        surface = raw.gsub(/\A[^\p{L}\p{N}]+|[^\p{L}\p{N}]+\z/, "")
        Token.new(NUMBERS.key?(key) ? NUMBERS[key].to_s : surface, NUMBERS.key?(key) ? NUMBERS[key].to_s : key)
      end
    end

    # Filler off both ends, repeatedly: "ich brauche noch bitte Milch".
    def trim(tokens)
      tokens = tokens.dup
      loop do
        before = tokens.size
        tokens = drop_phrase(tokens, leading_phrases, :front)
        tokens = drop_phrase(tokens, trailing_phrases, :back)
        break if tokens.size == before || tokens.empty?
      end
      tokens
    end

    def drop_phrase(tokens, phrases, side)
      longest = [ tokens.size, phrases[:max] ].min
      longest.downto(1) do |n|
        slice = side == :front ? tokens.first(n) : tokens.last(n)
        next unless phrases[:set].include?(slice.map(&:key).join(" "))

        return side == :front ? tokens.drop(n) : tokens[0...-n]
      end
      tokens
    end

    # Left to right, the longest known phrase wins ("olive oil" over "oil").
    # Returns the lines and whether any dictionary phrase was found.
    def segment(tokens)
      pieces = []
      pending = []
      matched = false
      i = 0

      while i < tokens.size
        n = match_length(tokens, i)
        if n.zero?
          pending << tokens[i]
          i += 1
          next
        end

        matched = true
        phrase = tokens[i, n]
        if prefix?(pending)
          phrase = pending + phrase
        else
          pieces << join(pending) if pending.any?
        end
        pieces << join(phrase)
        pending = []
        i += n
      end

      pieces << join(pending) if pending.any?
      [ pieces.reject(&:blank?), matched ]
    end

    def match_length(tokens, index)
      [ MAX_PHRASE_TOKENS, tokens.size - index ].min.downto(1).find do |n|
        dictionary.include?(tokens[index, n].map(&:key).join(" "))
      end.to_i
    end

    def prefix?(pending)
      return false if pending.empty?

      words = pending.reject { |t| t.key.match?(/\A\d+\z/) || UNITS.include?(t.key) }
      words.size <= MAX_PREFIX_TOKENS
    end

    def join(tokens) = tokens.map(&:surface).join(" ")

    def leading_phrases = @leading_phrases ||= phrase_set(LEADING)
    def trailing_phrases = @trailing_phrases ||= phrase_set(TRAILING)

    def phrase_set(list)
      keys = list.map { |p| ProductAlias.normalize_key(p) }
      { set: keys.to_set, max: keys.map { |k| k.split.size }.max }
    end

    # Everything this kitchen could mean by a word: the shared dictionary, its
    # own corrections, what it has put on a list or into the fridge before, and
    # the staples the suggester knows in both languages.
    def dictionary
      @dictionary ||= begin
        aliases = ProductAlias.shared
        aliases = ProductAlias.where(household_id: [ nil, @household.id ]) if @household
        words = aliases.pluck(:raw_text, :canonical_name).flatten
        words += Memo::Suggester::STAPLES.flat_map { |label, _category, word| [ label, word ] }
        words += @household.items.order(id: :desc).limit(500).pluck(:canonical_name) if @household
        known = keys(words)
        known.merge(past_memo_lines(known))
      end
    end

    # A past line is a phrase worth knowing ("toilet paper") — unless it is two
    # known words run together. The old splitter wrote lines like "bread milk",
    # and learning those would glue the same mistake onto every later list.
    def past_memo_lines(known)
      return [] unless @household

      keys(@household.memo_items.order(id: :desc).limit(500).pluck(:canonical_name)).reject do |line|
        tokens = line.split
        tokens.size > 1 && tokens.all? { |t| known.include?(t) }
      end
    end

    def keys(words) = words.filter_map { |w| ProductAlias.normalize_key(w).presence }.to_set
  end
end
