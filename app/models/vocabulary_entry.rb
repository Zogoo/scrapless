# What one kitchen has taught the memo mic by correcting it: an item phrase it
# did not know ("hafer drink"), or filler it says before or after items
# ("ich hätt gern"). Learned per kitchen and used only there, like the
# household layer of ProductAlias (doc 7 B6). Written by
# Memo::LearnFromCorrection, read by Text::Lexicon.
class VocabularyEntry < ApplicationRecord
  KINDS = %w[item leading trailing].freeze

  belongs_to :household

  validates :kind, inclusion: { in: KINDS }
  validates :phrase, presence: true, length: { maximum: 120 }, uniqueness: { scope: %i[household_id kind] }

  normalizes :phrase, with: ->(p) { ProductAlias.normalize_key(p) }
end
