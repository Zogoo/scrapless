# One billed call to the model provider. Exists because "cheapest model" is a
# claim that has to survive contact with an invoice: every call records what it
# cost, so cost per capture is measured rather than estimated.
class AiCall < ApplicationRecord
  belongs_to :household, optional: true

  validates :purpose, :model, presence: true

  scope :succeeded, -> { where(success: true) }

  def cost_usd = cost_micros / 1_000_000.0
end
