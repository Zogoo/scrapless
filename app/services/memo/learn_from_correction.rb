module Memo
  # A person renamed a line the mic wrote. That correction is the best evidence
  # we will ever get about how this kitchen speaks, so it is kept:
  #
  # - the new name is an item phrase, so "hafer drink" said again stays one
  #   line instead of two;
  # - if the new name is the old one with words cut off the front or the back
  #   ("Ich hätt gern Milch" -> "Milch"), those words are this kitchen's filler
  #   and are dropped next time.
  #
  # Words cut off that are themselves known items are not filler: "tortillas
  # milk" trimmed to "tortillas" means two items were glued together, not that
  # "milk" is a word to ignore.
  #
  # Learned per kitchen only (doc 7 B6: a free fridge must not teach everyone).
  # Only lines the mic wrote are learned from; a typed line has no mistake of
  # ours in it.
  class LearnFromCorrection < ApplicationService
    def initialize(item:, previous_name:)
      @item = item
      @before = ProductAlias.normalize_key(previous_name).split
      @after = ProductAlias.normalize_key(item.name).split
    end

    def call
      return unless @item.source == "voice" && @after.any? && @after != @before

      learn("item", @after)
      start = cut_position
      return unless start

      learn_filler("leading", @before[0...start])
      learn_filler("trailing", @before[(start + @after.size)..])
    end

    private

    # Where the new name sits inside the old one, if it is a contiguous part
    # of it; nil when the person rewrote the line rather than trimming it.
    def cut_position
      return if @after.size >= @before.size

      (0..(@before.size - @after.size)).find { |i| @before[i, @after.size] == @after }
    end

    def learn_filler(kind, words)
      return if words.blank?
      return if words.any? { |word| known_items.include?(word) } || known_items.include?(words.join(" "))

      learn(kind, words)
    end

    def known_items = @known_items ||= Text::Lexicon.for(@item.household).items

    def learn(kind, words)
      return if words.blank?

      @item.household.vocabulary_entries.find_or_create_by!(kind: kind, phrase: words.join(" "))
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
