module Memo
  # Which store section a shopping line belongs to (Categories::NAMES), so the
  # list reads like a walk through the shop. Shared by MemoItem and
  # Memo::Suggester.
  #
  # What this kitchen already knows wins over a guess:
  #   1. the household's own items of that name (what it was read as before)
  #   2. the dictionary, this kitchen's entries first, then the shared one
  #   3. Categories.guess from the words
  #   4. "other"
  #
  # One instance looks the household's items up once, for a whole list.
  class CategoryFor
    def self.call(name:, household:) = new(household: household).call(name)

    def initialize(household:)
      @household = household
    end

    def call(name)
      key = name.to_s.strip.squeeze(" ").downcase
      return "other" if key.blank?

      known[key] || from_dictionary(name) || guessed(name) || "other"
    end

    private

    def known
      @known ||= @household ? @household.items.order(:id).pluck(:canonical_name, :category).to_h : {}
    end

    def from_dictionary(name)
      category = ProductAlias.lookup(name, household: @household, fuzzy: false)&.category
      category if Categories.valid?(category)
    end

    def guessed(name)
      category = Categories.guess(name)
      category if Categories.valid?(category)
    end
  end
end
