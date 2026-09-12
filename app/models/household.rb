# A fridge. The tenant for everything else.
#
# There is no user account: doc 2 §2.7 makes "value before permission, permission
# before account" a rule, so identity is an opaque token the browser keeps in
# localStorage and a ten-year cookie. Losing both loses the fridge, which is the
# accepted trade for having no sign-up screen.
class Household < ApplicationRecord
  TOKEN_LIFETIME = 10.years

  ADJECTIVES = %w[Quiet Bright Amber Copper Nordic Little Corner Green Warm Sunny Blue Old].freeze
  NOUNS = %w[Kitchen Fridge Larder Pantry Icebox Crisper Cellar Kombüse].freeze

  has_many :items, dependent: :destroy
  has_many :captures, dependent: :destroy
  has_many :item_events, dependent: :destroy
  has_many :memo_items, dependent: :destroy

  validates :name, presence: true, length: { maximum: 60 }
  validates :uuid, :token, presence: true, uniqueness: true

  before_validation :assign_identity, on: :create

  normalizes :name, with: ->(n) { n.to_s.strip.presence }

  def self.random_name
    "#{ADJECTIVES.sample} #{NOUNS.sample}"
  end

  def touch_seen!
    update_column(:last_seen_at, Time.current) if last_seen_at.nil? || last_seen_at < 1.hour.ago
  end

  private

  def assign_identity
    self.uuid  ||= SecureRandom.uuid
    self.token ||= SecureRandom.urlsafe_base64(32)
    self.name  ||= self.class.random_name
  end
end
