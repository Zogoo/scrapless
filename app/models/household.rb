# A fridge. The tenant for everything else.
#
# There is no user account: doc 2 §2.7 makes "value before permission, permission
# before account" a rule, so identity is an opaque token the browser keeps in
# localStorage and a ten-year cookie. Losing both, on every phone that has
# opened the kitchen, loses the fridge. That is the accepted trade for having
# no sign-up screen.
#
# `token` is the bearer secret. `join_code` is a different secret used only to
# open the kitchen on another phone; it is not accepted as a bearer.
class Household < ApplicationRecord
  TOKEN_LIFETIME = 10.years

  ADJECTIVES = %w[Quiet Bright Amber Copper Nordic Little Corner Green Warm Sunny Blue Old].freeze
  NOUNS = %w[Kitchen Fridge Larder Pantry Icebox Crisper Cellar Kombüse].freeze

  has_many :items, dependent: :destroy
  has_many :captures, dependent: :destroy
  has_many :item_events, dependent: :destroy
  has_many :memo_items, dependent: :destroy

  validates :name, presence: true, length: { maximum: 60 }
  validates :uuid, :token, :join_code, presence: true, uniqueness: true

  before_validation :assign_identity, on: :create

  normalizes :name, with: ->(n) { n.to_s.strip.presence }

  def self.random_name
    "#{ADJECTIVES.sample} #{NOUNS.sample}"
  end

  # 16 bytes, URL-safe, and a different length from the bearer token so the two
  # can never be confused for each other by eye.
  def self.generate_join_code
    loop do
      code = SecureRandom.urlsafe_base64(16)
      break code unless exists?(join_code: code)
    end
  end

  def touch_seen!
    update_column(:last_seen_at, Time.current) if last_seen_at.nil? || last_seen_at < 1.hour.ago
  end

  private

  def assign_identity
    self.uuid      ||= SecureRandom.uuid
    self.token     ||= SecureRandom.urlsafe_base64(32)
    self.join_code ||= self.class.generate_join_code
    self.name      ||= self.class.random_name
  end
end
