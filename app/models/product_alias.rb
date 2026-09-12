# Receipt jargon -> a name a human recognises. Every confirmed mapping makes the
# next parse cheaper, because a hit here skips the model call entirely.
class ProductAlias < ApplicationRecord
  validates :raw_text, :canonical_name, :category, presence: true

  normalizes :raw_text, with: ->(t) { ProductAlias.normalize_key(t) }

  def self.normalize_key(text)
    text.to_s.downcase.gsub(/[^a-z0-9äöüß ]/, " ").squeeze(" ").strip
  end

  # Exact match first, then the same words in any order — enough to catch
  # "BROKKOLI 500G" against a stored "brokkoli" without a fuzzy-match library.
  def self.lookup(raw_text, merchant: nil)
    key = normalize_key(raw_text)
    return nil if key.blank?

    scope = where(raw_text: key)
    scope.where(merchant: merchant).first ||
      scope.where(merchant: nil).first ||
      scope.first ||
      token_match(key)
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

  def self.record_correction!(raw_text:, canonical_name:, category:, merchant: nil, emoji: nil)
    key = normalize_key(raw_text)
    return if key.blank?

    entry = find_or_initialize_by(raw_text: key, merchant: merchant)
    entry.canonical_name = canonical_name
    entry.category = category
    entry.emoji ||= emoji
    entry.votes = entry.persisted? ? entry.votes + 1 : 1
    entry.save
  end
end
