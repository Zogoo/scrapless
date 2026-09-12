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

  def self.token_match(key)
    tokens = key.split
    return nil if tokens.empty?

    candidates = where("raw_text LIKE ?", "%#{tokens.first}%").limit(50)
    candidates.max_by { |a| (a.raw_text.split & tokens).size }&.then do |best|
      (best.raw_text.split & tokens).any? ? best : nil
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
