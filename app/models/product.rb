# One kind of food, whatever it is called: "H-MILCH 3,5%" on a REWE till,
# "Milch" typed in German and "Milk" said in English are one product, "milk".
#
# The key is the model's generic English name (doc 5 §5.3, PRODUCT), written
# in one language on purpose: it is never shown, it only has to come out the
# same for the same food, in every kitchen and every UI language.
#
# What a product is *not* is a shelf life. The key is a model's judgement and
# can be coarser than the food ("cheese" for a fresh and an aged one), so
# windows still come from each line's category and storage.
class Product < ApplicationRecord
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
  def self.for(key)
    normalized = normalize_key(key)
    return nil if normalized.blank?

    create_or_find_by!(key: normalized)
  end

  # Every name this food has been seen under, in any language: the receipt
  # spellings and the names people were shown.
  def names
    product_aliases.pluck(:raw_text, :canonical_name).flatten.uniq.sort
  end
end
