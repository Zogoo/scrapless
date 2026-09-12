# A hypothesis about food in the fridge, not a fact.
#
# The window (start..end) rather than a single `expires_on` is deliberate: it is
# structurally impossible for the UI to render a precision we do not have.
class Item < ApplicationRecord
  STORAGES = %w[fridge freezer pantry].freeze
  STATES = %w[active rescued wasted retired].freeze
  DATE_LABEL_TYPES = %w[none mhd verbrauchsdatum].freeze

  belongs_to :household
  belongs_to :capture, optional: true
  has_many :item_events, dependent: :destroy

  validates :display_name, :canonical_name, presence: true
  validates :storage, inclusion: { in: STORAGES }
  validates :state, inclusion: { in: STATES }
  validates :date_label_type, inclusion: { in: DATE_LABEL_TYPES }
  validate :window_ordered

  scope :active, -> { where(state: "active") }
  scope :by_urgency, -> { order(:window_end, :id) }

  normalizes :canonical_name, with: ->(n) { n.to_s.strip.downcase.presence }

  def high_risk? = date_label_type == "verbrauchsdatum"

  # How far through its life the food is, measured from the day it came home to
  # the far end of the uncertainty band. This is what the decay bar draws, and it
  # is deliberately *not* the position inside the band: a bar that reads empty
  # for the first 70% of a broccoli's life tells the user nothing.
  def life_fraction(on = Date.current)
    span = (window_end - acquired_on).to_i
    return 1.0 if span <= 0

    ((on - acquired_on).to_i / span.to_f).clamp(0.0, 3.0)
  end

  def days_left(on = Date.current) = (window_end - on).to_i

  def frozen_storage? = storage == "freezer"

  private

  def window_ordered
    return if window_start.blank? || window_end.blank?

    errors.add(:window_end, "must not be before window_start") if window_end < window_start
  end
end
