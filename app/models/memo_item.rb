# A line on the shopping memo. Deliberately not modelled as an Item: a thing you
# intend to buy and a thing that is rotting are different objects with different
# lifecycles, and conflating them is how "running low" lists become inventory.
class MemoItem < ApplicationRecord
  SOURCES = %w[voice text suggestion auto].freeze

  belongs_to :household

  validates :name, presence: true, length: { maximum: 120 }
  validates :source, inclusion: { in: SOURCES }

  scope :open, -> { where(done: false) }
  scope :ordered, -> { order(:done, :position, :id) }

  normalizes :name, with: ->(n) { n.to_s.strip.squeeze(" ").presence }

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
