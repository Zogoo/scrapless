# A line on the shopping memo. Deliberately not modelled as an Item: a thing you
# intend to buy and a thing that is rotting are different objects with different
# lifecycles, and conflating them is how "running low" lists become inventory.
class MemoItem < ApplicationRecord
  include AddedBy

  SOURCES = %w[voice text suggestion auto].freeze

  belongs_to :household

  validates :name, presence: true, length: { maximum: 120 }
  validates :source, inclusion: { in: SOURCES }
  validates :category, inclusion: { in: Categories::NAMES }
  validates :quantity, numericality: { only_integer: true, in: 1..Memo::Quantity::MAX }

  scope :open, -> { where(done: false) }
  scope :ordered, -> { order(:done, :position, :id) }

  # The open line for this name, if one is already on the list: the same
  # name, or the same food under another name the dictionary knows ("Apfel"
  # and "Äpfel" both being apple).
  def self.open_line_for(name)
    key = name.to_s.strip.squeeze(" ").downcase
    open.find_by(canonical_name: key) || open_line_for_product(name)
  end

  def self.open_line_for_product(name)
    product_id = ProductAlias.lookup(name, fuzzy: false)&.product_id
    return nil if product_id.nil?

    open.find { |line| ProductAlias.lookup(line.name, fuzzy: false)&.product_id == product_id }
  end

  # One capitalisation for every way in: typed "gouda" and a suggested "Gouda"
  # used to sit on the list as two different-looking lines.
  normalizes :name, with: ->(n) { n.to_s.strip.squeeze(" ").upcase_first.presence }

  before_validation :derive_canonical_name
  # The store section the list groups it under; read again when renamed.
  before_validation :assign_category, if: -> { new_record? || will_save_change_to_name? }
  before_create :assign_position

  private

  def derive_canonical_name
    self.canonical_name = name.to_s.strip.downcase.presence
  end

  def assign_category
    self.category = Memo::CategoryFor.call(name: name, household: household)
  end

  def assign_position
    self.position = (household.memo_items.maximum(:position) || 0) + 1
  end
end
