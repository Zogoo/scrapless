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
  # Takes several spellings of one line — the raw text first, it is the
  # evidence; then the model's name — and tries every exact match before any
  # fuzzy one. Each is also tried without its quantities, because tills print
  # them inline: "H-MILCH 3,5%" is H-Milch and "2 milch" is Milch, exactly.
  # (One spelling at a time, a fuzzy "2 milch" once beat the exact "Milch";
  # names before raw text, "Milk" once beat the receipt's "H-MILCH".)
  #
  # The kitchen's own corrections are tried before the shared dictionary at
  # each step, but an exact shared hit still beats a fuzzy household one.
  #
  # `fuzzy: false` stops after the exact matches (see Items::Resolver).
  def self.lookup(texts, merchant: nil, household: nil, fuzzy: true)
    keys = Array(texts).flat_map { |text| [ normalize_key(text), without_quantities(normalize_key(text)) ] }
                       .reject(&:blank?).uniq
    return nil if keys.empty?

    layers = [ household && where(household: household), shared ].compact
    exact = first_hit(layers, keys) { |layer, key| layer.exact_match(key, merchant) }
    return exact if exact || !fuzzy

    first_hit(layers, keys) { |layer, key| layer.token_match(key) }
  end

  # "h milch 3 5" -> "h milch"; "babyspinat 260g" -> "babyspinat".
  def self.without_quantities(key) = key.split.grep_v(/\d/).join(" ")

  def self.first_hit(layers, keys)
    layers.each do |layer|
      keys.each do |key|
        hit = yield(layer, key)
        return hit if hit
      end
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
    # On a tie, the entry that leaves fewer of its own words unexplained wins:
    # "milch 1l" is "milch", not "h milch". Before, row order decided.
    scored.max_by { |entry, score| [ score, -unmatched(entry.raw_text.split, tokens) ] }&.first
  end

  # One point per token pair where either is a prefix of the other, so a
  # truncation still counts as agreement.
  def self.overlap(stored, tokens)
    stored.sum { |s| tokens.count { |t| agree?(s, t) } }
  end

  def self.unmatched(stored, tokens)
    stored.count { |s| tokens.none? { |t| agree?(s, t) } }
  end

  def self.agree?(stored, token)
    stored.start_with?(token[0, MIN_PREFIX]) || token.start_with?(stored[0, MIN_PREFIX])
  end

  # As a person would write it: "H-Milch" stays "H-Milch" (titleize made it
  # "H Milch"), and a kitchen's own "bread rolls" reads "Bread rolls".
  def display_name = canonical_name.upcase_first

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
