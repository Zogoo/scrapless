# Append-only audit log. `Item` stays the source of truth for current state —
# this is explicitly not a projection (doc 5 §5.3), which keeps erasure a plain
# row delete rather than crypto-shredding an immutable log.
class ItemEvent < ApplicationRecord
  KINDS = %w[captured used partial_use wasted frozen opened snoozed corrected retired].freeze

  belongs_to :item
  belongs_to :household

  validates :kind, inclusion: { in: KINDS }
  validates :at, presence: true

  before_validation { self.at ||= Time.current }

  scope :recent, -> { order(at: :desc) }

  def meta_payload = meta.present? ? JSON.parse(meta) : {}

  def meta_payload=(hash)
    self.meta = hash.to_json
  end
end
