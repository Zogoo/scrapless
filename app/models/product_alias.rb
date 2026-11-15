# Receipt jargon -> a name a human recognises. Every confirmed mapping makes the
# next parse cheaper, because a hit here skips the model call entirely.
#
# Two layers. Rows with no household are the shared dictionary — seeded, and
# never written by a request. Rows with a household are that kitchen's own
# corrections, and they win inside that kitchen only. Doc 5 §5.6 and doc 7 B6:
# a free, anonymous fridge must not be able to rename "milch" for everyone.
class ProductAlias < ApplicationRecord
  belongs_to :household, optional: true

  scope :shared, -> { where(household_id: nil) }

  validates :raw_text, :canonical_name, :category, presence: true

  normalizes :raw_text, with: ->(t) { ProductAlias.normalize_key(t) }

  def self.normalize_key(text)
    text.to_s.downcase.gsub(/[^a-z0-9äöüß ]/, " ").squeeze(" ").strip
  end

  # Exact match first, then the same words in any order — enough to catch
  # "BROKKOLI 500G" against a stored "brokkoli" without a fuzzy-match library.
  #
  # The kitchen's own corrections are tried before the shared dictionary at
  # each step, but an exact shared hit still beats a fuzzy household one.
  def self.lookup(raw_text, merchant: nil, household: nil)
    key = normalize_key(raw_text)
    return nil if key.blank?

    layers = [ household && where(household: household), shared ].compact
    layers.each do |layer|
      hit = layer.exact_match(key, merchant)
      return hit if hit
    end
    layers.each do |layer|
      hit = layer.token_match(key)
      return hit if hit
    end
    nil
  end

  def self.exact_match(key, merchant)
    scope = where(raw_text: key)
    scope.where(merchant: merchant).first || scope.where(merchant: nil).first || scope.first
  end

  # Receipts truncate. "RISPENTOMAT." is the same tomato as "rispentomaten" and
  # "HAEHNCH.SCHENK." the same chicken as "haehnchenschenkel", so a shared *exact*
  # token is too strict a test — it was rejecting prefix matches the LIKE had
  # already found, and a mis-filed tomato got a 180-day pantry window.
  MIN_PREFIX = 4

  def self.token_match(key)
    tokens = key.split.reject { |t| t.length < MIN_PREFIX }
    return nil if tokens.empty?

    candidates = where(tokens.map { "raw_text LIKE ?" }.join(" OR "),
                       *tokens.map { |t| "%#{t[0, MIN_PREFIX]}%" }).limit(50)

    scored = candidates.map { |entry| [ entry, overlap(entry.raw_text.split, tokens) ] }
                       .reject { |_, score| score.zero? }
    scored.max_by { |_, score| score }&.first
  end

  # One point per token pair where either is a prefix of the other, so a
  # truncation still counts as agreement.
  def self.overlap(stored, tokens)
    stored.sum do |s|
      tokens.count { |t| s.start_with?(t[0, MIN_PREFIX]) || t.start_with?(s[0, MIN_PREFIX]) }
    end
  end

  # Writes to the correcting kitchen's layer only. The shared dictionary is
  # changed by a seed or a reviewed promotion, never by a request.
  def self.record_correction!(household:, raw_text:, canonical_name:, category:, merchant: nil, emoji: nil)
    key = normalize_key(raw_text)
    return if key.blank? || household.nil?

    entry = find_or_initialize_by(household: household, raw_text: key, merchant: merchant)
    entry.canonical_name = canonical_name
    entry.category = category
    entry.emoji ||= emoji
    entry.votes = entry.persisted? ? entry.votes + 1 : 1
    entry.save
  end
end
