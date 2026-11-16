# One notification spent from a kitchen's weekly budget (doc 5 §5.5).
#
# The row is written before anything is sent and the unique indexes make it the
# lock: a second tick, or two ticks at once, cannot spend the same slot or send
# twice on the same day. Delivery to each phone is a job of its own.
class Notification < ApplicationRecord
  MAX_PER_WEEK = 3

  belongs_to :household

  validates :iso_week, :sent_on, presence: true
  validates :slot, inclusion: { in: 1..MAX_PER_WEEK }

  # ISO 8601 week-year, so the last days of December can belong to week 1.
  def self.week_of(date) = date.strftime("%G-W%V")

  def items = household.items.where(id: item_ids)
end
