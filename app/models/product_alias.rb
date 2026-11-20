# Receipt jargon -> a name a human recognises. Every confirmed mapping makes the
# next parse cheaper, because a hit here skips the model call entirely.
#
# Two layers. Rows with no household are the shared dictionary — seeded, or
# promoted once five kitchens agree; never written on one request's own say.
# Rows with a household are that kitchen's own
# corrections, and they win inside that kitchen only. Doc 5 §5.6 and doc 7 B6:
# a free, anonymous fridge must not be able to rename "milch" for everyone.
#
# A third way in: when the model reads a line the dictionary did not know
# exactly, the server keeps its answer for that kitchen (`learn!`), so the next
# time it is typed or spoken there it costs nothing. Once five independent
# kitchens agree on what a spelling is, it is shared with everyone
# (`promote!`) — doc 5 §5.6's k ≥ 5.
class ProductAlias < ApplicationRecord
  # Doc 5 §5.6 and doc 7 B6: global promotion needs k ≥ 5 independent kitchens.
  PROMOTE_AT = 5
  SOURCES = %w[seed correction ai promoted].freeze

  belongs_to :household, optional: true
  belongs_to :product, optional: true

  scope :shared, -> { where(household_id: nil) }

  validates :source, inclusion: { in: SOURCES }
  validates :storage, inclusion: { in: Item::STORAGES }, allow_nil: true

  validates :raw_text, :canonical_name, :category, presence: true

  normalizes :raw_text, with: ->(t) { ProductAlias.normalize_key(t) }

  # "Hähnchenbrust" and "HAEHNCHENBRUST" are one key: every locale's
  # transliteration rules (config/locales) are applied, and any other letter,
  # in any script, is kept as it is.
  def self.normalize_key(text)
    key = text.to_s.downcase
    key = key.gsub(Regexp.union(spelling_pairs.keys), spelling_pairs) if spelling_pairs.any?
    key.gsub(/[^\p{L}\p{N} ]/, " ").squeeze(" ").strip
  end

  def self.spelling_pairs
    @spelling_pairs ||= I18n.available_locales.each_with_object({}) do |locale, pairs|
      rules = I18n.t("i18n.transliterate.rule", locale: locale, default: {})
      pairs.merge!(rules.to_h.transform_keys(&:to_s)) if rules.is_a?(Hash)
    end
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
  # changed by a seed or a promotion, never directly by a request. A correction
  # always wins over what the model said, and it is a vote like any other.
  def self.record_correction!(household:, raw_text:, canonical_name:, category:, merchant: nil, emoji: nil,
                              product: nil, source_product_key: nil)
    key = normalize_key(raw_text)
    return if key.blank? || household.nil?

    entry = find_or_initialize_by(household: household, raw_text: key, merchant: merchant)
    entry.assign_attributes(canonical_name: canonical_name, category: category, product: product,
                            source_product_key: source_key(source_product_key, product), source: "correction")
    entry.emoji ||= emoji
    entry.votes = entry.persisted? ? entry.votes + 1 : 1
    promote!(key) if entry.save
  end

  # The model's answer for a line the dictionary did not know exactly, kept for
  # this kitchen. Only the first answer is kept: an entry already there — the
  # model's, or the person's own correction — stands, and the dictionary stays
  # the thing that decides (doc 5 §5.3: dictionary first, model for the rest).
  #
  # Keyed without quantities, so "2 hähnchenbrust" teaches "hähnchenbrust".
  def self.learn!(household:, raw_text:, canonical_name:, category:, product:, storage: nil, emoji: nil,
                  source_product_key: nil)
    key = without_quantities(normalize_key(raw_text)).presence || normalize_key(raw_text)
    return if key.blank? || household.nil? || product.nil?
    return if exists?(household: household, raw_text: key)

    create!(household: household, raw_text: key, canonical_name: canonical_name, category: category,
            product: product, source_product_key: source_key(source_product_key, product), storage: storage,
            emoji: emoji, source: "ai")
    promote!(key)
  rescue ActiveRecord::RecordNotUnique
    nil # the same kitchen sent the same line twice at once; the first one won
  end

  # Where this kitchen keeps a food, learned from the person moving it
  # (Items::Resolve, Items::Correct): "Tomaten" go in the cupboard here, so the
  # next receipt puts them there. This kitchen only and never promoted — where
  # a food lives is a household's habit, not a fact about the food.
  #
  # Marked a correction, so it outranks the model's guess (Items::Resolver)
  # and survives forget!. It changes only the place, never what the food is.
  def self.remember_place!(household:, item:)
    raw = item.raw_text.presence || Copy.bare_name(item)
    exact = normalize_key(raw)
    key = without_quantities(exact).presence || exact
    return if key.blank? || household.nil? || !Item::STORAGES.include?(item.storage)

    entries = where(household: household, raw_text: [ key, exact ].uniq)
    if entries.exists?
      entries.update_all(storage: item.storage, source: "correction", updated_at: Time.current)
    else
      create!(household: household, raw_text: key, canonical_name: item.canonical_name, category: item.category,
              product: item.product, source_product_key: source_key(item.source_product_key, item.product),
              storage: item.storage, emoji: item.display_name[Copy::LEADING_EMOJI]&.strip,
              source: "correction")
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Takes back what the model taught this kitchen about a line, when the
  # person removed that line as read wrong. Their own corrections stay.
  def self.forget!(household:, raw_text:)
    key = without_quantities(normalize_key(raw_text)).presence || normalize_key(raw_text)
    return if key.blank?

    where(household: household, raw_text: key, source: "ai").delete_all
  end

  # The key the model gave before merging ("basmati rice" on a "rice" entry),
  # so Products::RecomputeMerges can move the entry if the merge list changes.
  def self.source_key(key, product) = Product.normalize_key(key).presence || product&.key

  # Shares a spelling with every kitchen once PROMOTE_AT of them, each on its
  # own, have said it is the same product. Runs on the write that cast the
  # vote, so there is no job to schedule and no queue to fall behind.
  #
  # It never overwrites a seeded entry, and never turns a high-risk food into
  # a lower-risk one (doc 7 B6): either would need a person to review it, so
  # those votes stay in each kitchen's own layer, where they already work.
  def self.promote!(key)
    votes = where.not(household_id: nil).where(raw_text: key).where.not(product_id: nil)
                 .group(:product_id).distinct.count(:household_id)
    product_id, kitchens = votes.max_by { |_, count| count }
    return if kitchens.nil? || kitchens < PROMOTE_AT

    agreeing = where.not(household_id: nil).where(raw_text: key, product_id: product_id)
    (canonical_name, category, storage), = agreeing.group(:canonical_name, :category, :storage).count
                                                   .max_by { |_, count| count }

    entry = shared.find_or_initialize_by(raw_text: key, merchant: nil)
    return if entry.source == "seed" || lowers_risk?(entry, category)

    entry.update!(canonical_name: canonical_name, category: category, storage: storage, product_id: product_id,
                  source_product_key: agreeing.where.not(source_product_key: nil).group(:source_product_key)
                                              .count.max_by { |_, count| count }&.first,
                  emoji: agreeing.where.not(emoji: nil).pick(:emoji), votes: kitchens, source: "promoted")
  end

  def self.lowers_risk?(entry, category)
    entry.persisted? && Categories.high_risk?(entry.category) && !Categories.high_risk?(category)
  end
end
