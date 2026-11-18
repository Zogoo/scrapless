module Text
  # One spoken or typed sentence -> the list lines in it, with no punctuation
  # needed and no model call.
  #
  # Browser recognisers return "I want to buy bread milk eggs" with no commas
  # (doc 15 §15.2.3), so this splits on what the kitchen's Text::Lexicon knows
  # rather than on punctuation alone:
  #
  # 1. punctuation, then the separator words of every language;
  # 2. spoken numbers become digits ("ein dutzend" -> 12);
  # 3. filler off both ends of each group ("ich brauche noch ... bitte");
  # 4. the longest known item phrase wins, left to right. Numbers, units and
  #    modifiers just before an item belong to it ("2 Flaschen Bio Milch");
  #    any other unknown words stay together as their own line ("toilet
  #    paper", "something for Sunday"), because a memo line need not be a
  #    known food.
  #
  # Every language's phrases are used at once: a Berlin list is often mixed.
  # No word list lives here; it is all config/dictation plus what the kitchen
  # has taught it.
  class Segmenter < ApplicationService
    # `sure` is true when every line is a known item, optionally preceded by an
    # amount, unit or modifier: nothing was left over that the lexicon could not
    # place. It is what Memo::ListReader uses to decide whether a model is
    # worth calling (doc 15 §15.11).
    Result = Struct.new(:parts, :unresolved, :sure, keyword_init: true)
    Token = Struct.new(:surface, :key, :role, keyword_init: true)

    # Language-neutral marks. A full stop splits, a decimal point does not.
    PUNCTUATION = /[,;\n]|\.(?!\d)/
    # A safety bound on one request, not a property of speech.
    MAX_PARTS = 25

    def initialize(text:, household: nil, lexicon: nil)
      @text = text.to_s
      @lexicon = lexicon || Lexicon.for(household)
    end

    def call
      parts = []
      unresolved = []
      @leftover = false

      groups.each do |tokens|
        tokens = trim(tokens)
        next if tokens.empty?

        pieces, matched = segment(tokens)
        # A group of several words with nothing recognised is where a model
        # would have helped; it is reported so that is measured, not guessed.
        unresolved << join(tokens) if !matched && tokens.size > 1
        parts.concat(pieces)
      end

      Result.new(parts: parts.first(MAX_PARTS), unresolved: unresolved,
                 sure: !@leftover && parts.size <= MAX_PARTS)
    end

    private

    attr_reader :lexicon

    def groups
      @text.split(PUNCTUATION).flat_map do |chunk|
        tokens = numbers_as_digits(tokenize(chunk))
        tokens.slice_when { |a, b| separator?(a) || separator?(b) }.reject { |g| g.all? { |t| separator?(t) } }
      end
    end

    def tokenize(chunk)
      chunk.split(/\s+/).filter_map do |raw|
        key = ProductAlias.normalize_key(raw)
        next if key.blank?

        Token.new(surface: raw.gsub(/\A[^\p{L}\p{N}]+|[^\p{L}\p{N}]+\z/, ""), key: key)
      end
    end

    def separator?(token) = lexicon.separators.include?(token.key)

    def numbers_as_digits(tokens)
      out = []
      i = 0
      while i < tokens.size
        n = longest_match(tokens, i, lexicon.numbers, lexicon.numbers_longest)
        if n.positive?
          value = lexicon.numbers[key_of(tokens[i, n])].to_s
          out << Token.new(surface: value, key: value)
          i += n
        else
          out << tokens[i]
          i += 1
        end
      end
      out
    end

    # Filler off both ends, repeatedly: "ich brauche noch bitte Milch".
    def trim(tokens)
      loop do
        before = tokens.size
        n = longest_match(tokens, 0, lexicon.leading, lexicon.leading_longest)
        tokens = tokens.drop(n)
        n = longest_suffix(tokens, lexicon.trailing, lexicon.trailing_longest)
        tokens = tokens[0...(tokens.size - n)]
        return tokens if tokens.size == before || tokens.empty?
      end
    end

    # Returns the lines and whether any known item was found.
    def segment(tokens)
      pieces = []
      pending = []
      matched = false
      i = 0

      while i < tokens.size
        n = longest_match(tokens, i, lexicon.items, lexicon.items_longest)
        if n.positive?
          matched = true
          attached = pending.reverse.take_while { |t| t.role == :attachable }.reverse
          loose = pending[0...(pending.size - attached.size)]
          flush(pieces, loose)
          pieces << join(attached + tokens[i, n])
          pending = []
          i += n
          next
        end

        m = attachable_length(tokens, i)
        if m.positive?
          tokens[i, m].each { |t| pending << Token.new(surface: t.surface, key: t.key, role: :attachable) }
          i += m
        else
          pending << tokens[i]
          i += 1
        end
      end

      flush(pieces, pending)
      [ pieces, matched ]
    end

    # Words that describe the item after them: an amount, a unit, a modifier.
    def attachable_length(tokens, index)
      return 1 if tokens[index].key.match?(/\A\d+(?:[.,]\d+)?\z/)
      return 1 if lexicon.units.include?(tokens[index].key)

      longest_match(tokens, index, lexicon.modifiers, lexicon.modifiers_longest)
    end

    # Unknown words between items are one line, with filler trimmed off it.
    # Nothing else is dropped: every word said ends up in a line or was filler.
    def flush(pieces, run)
      run = trim(run)
      return if run.empty?

      @leftover = true
      pieces << join(run)
    end

    def longest_match(tokens, index, set, longest)
      [ longest, tokens.size - index ].min.downto(1).find { |n| set.include?(key_of(tokens[index, n])) }.to_i
    end

    def longest_suffix(tokens, set, longest)
      [ longest, tokens.size ].min.downto(1).find { |n| set.include?(key_of(tokens.last(n))) }.to_i
    end

    def key_of(tokens) = tokens.map(&:key).join(" ")

    def join(tokens) = tokens.map(&:surface).join(" ")
  end
end
