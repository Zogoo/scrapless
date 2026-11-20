# One kind of food, whatever it is called: "H-MILCH 3,5%" on a REWE till,
# "Milch" typed in German and "Milk" said in English are one product, "milk".
#
# The key is the model's generic English name (doc 5 §5.3, PRODUCT), written
# in one language on purpose: it is never shown, it only has to come out the
# same for the same food, in every kitchen and every UI language.
#
# A product also carries a shelf life per place (`shelf_life`), asked of the
# model once, the first time any kitchen meets the food (Products::LearnShelfLife),
# and then shared. The key can still be coarser than the food ("cheese" for a
# fresh and an aged one), so the model is told to answer for the most
# perishable common form, and Freshness::Estimator caps high-risk food at its
# category's limit. A printed date always wins over it.
class Product < ApplicationRecord
  PLACES = %w[fridge freezer pantry].freeze
  # Three years: past this a number is a guess about the packaging, not food.
  MAX_DAYS = 1095

  # What both readers are told, so a photo and a typed word land on one key.
  PROMPT_RULE = <<~RULE.squish
    product is the food's generic name translated into English, in American
    spelling, lowercase and singular. Always English, even when the name and everything else is German:
    it is a key for matching, never shown. Specific enough to buy the same thing
    again, nothing more: no brand, size, weight, fat content, packaging or
    offer. "H-MILCH 3,5%" is "uht milk", "Vollmilch" is "milk",
    "HAEHNCHENSCHENKEL" is "chicken thigh", "Babyspinat 260g" is "baby spinach".
  RULE

  has_many :product_aliases, dependent: :nullify
  has_many :items, dependent: :nullify

  normalizes :key, with: ->(key) { Product.normalize_key(key) }
  validates :key, presence: true

  def self.normalize_key(key) = key.to_s.downcase.gsub(/[^[:alnum:] ]/, " ").squeeze(" ").strip

  # nil for a blank key, so a line the model gave no product for stays loose.
  #
  # With a category, interchangeable varieties become one product first
  # (Products::MergeKey, config/product_merge.yml): "basmati rice" is "rice".
  # The caller keeps the key it started from on the item (source_product_key),
  # so a change to the merge list can be recomputed and split back apart.
  def self.for(key, category: nil)
    normalized = normalize_key(key)
    return nil if normalized.blank?

    normalized = Products::MergeKey.call(key: normalized, category: category) if category
    create_or_find_by!(key: normalized).tap(&:name_from_config!)
  end

  # The title a Kitchen line shows when varieties stack ("Reis" over a
  # basmati and a jasmine pack). Written once, from the merge list.
  def name_from_config!
    return self if names.present?

    title = Products::MergeKey.name_for(key, :de)
    update!(names: { "de" => title }) if title
    self
  end

  def name_in(locale) = names.is_a?(Hash) ? names[locale.to_s].presence : nil

  # { typical:, max:, opened: } in days for one place, or nil when the product
  # is not kept there or nothing is known yet. Re-checked on read, so a bad row
  # degrades to the category rule rather than to a wrong window.
  def shelf_life_for(storage)
    Product.clean_place(shelf_life.is_a?(Hash) ? shelf_life[storage.to_s] : nil)
  end

  def shelf_life_known? = shelf_life.is_a?(Hash) && PLACES.any? { |place| shelf_life_for(place) }

  # One place from the model, or nil when it is not a usable answer.
  def self.clean_place(value)
    return nil unless value.is_a?(Hash)

    typical, max, opened = %w[typical max opened].map { |k| whole_days(value[k] || value[k.to_sym]) }
    return nil if typical.nil? || max.nil? || typical > max

    { typical: typical, max: max, opened: opened && [ opened, max ].min }
  end

  def self.whole_days(value)
    days = Integer(value, exception: false) || Float(value, exception: false)&.round
    days if days&.between?(1, MAX_DAYS)
  end

  # Every name this food has been seen under, in any language: the receipt
  # spellings and the names people were shown. (`names` is the column of line
  # titles per language.)
  def seen_names
    product_aliases.pluck(:raw_text, :canonical_name).flatten.uniq.sort
  end
end
