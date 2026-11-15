# A line on the shopping memo. Deliberately not modelled as an Item: a thing you
# intend to buy and a thing that is rotting are different objects with different
# lifecycles, and conflating them is how "running low" lists become inventory.
class MemoItem < ApplicationRecord
  include AddedBy

  SOURCES = %w[voice text suggestion auto].freeze

  belongs_to :household

  validates :name, presence: true, length: { maximum: 120 }
  validates :source, inclusion: { in: SOURCES }

  scope :open, -> { where(done: false) }
  scope :ordered, -> { order(:done, :position, :id) }

  # The open line for this name, if one is already on the list.
  def self.open_line_for(name)
    open.find_by(canonical_name: name.to_s.strip.squeeze(" ").downcase)
  end

  # One capitalisation for every way in: typed "gouda" and a suggested "Gouda"
  # used to sit on the list as two different-looking lines.
  normalizes :name, with: ->(n) { n.to_s.strip.squeeze(" ").upcase_first.presence }

  before_validation :derive_canonical_name
  before_create :assign_position

  private

  def derive_canonical_name
    self.canonical_name = name.to_s.strip.downcase.presence
  end

  def assign_position
    self.position = (household.memo_items.maximum(:position) || 0) + 1
  end
end
