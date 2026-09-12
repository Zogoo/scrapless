# One act of telling the app what you bought — a receipt photo, a shelf photo,
# a spoken sentence or a typed line. Keeps the raw model response so a bad parse
# can be audited, diffed against the user's correction and retrained on.
class Capture < ApplicationRecord
  SOURCES = %w[receipt shelf_photo voice text grid].freeze
  STATUSES = %w[pending parsed failed].freeze

  belongs_to :household
  has_many :items, dependent: :nullify
  has_one_attached :image
  has_one_attached :audio

  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def raw_payload = raw_response.present? ? JSON.parse(raw_response) : {}

  def raw_payload=(hash)
    self.raw_response = hash.to_json
  end
end
