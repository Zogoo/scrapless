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

  # How the household eats, said once (onboarding or Settings). nil means "not
  # asked yet", which is different from "all" or 0. A list of foods to leave
  # out, never a medical claim: the app does not know about allergies.
  DIETS = %w[all vegetarian vegan].freeze
  BROTBOXEN = 0..6
  MAX_EXCLUDED = 20
  MAX_EXCLUDED_LENGTH = 40

  has_many :items, dependent: :destroy
  has_many :captures, dependent: :destroy
  has_many :item_events, dependent: :destroy
  has_many :memo_items, dependent: :destroy
  has_many :product_aliases, dependent: :destroy
  has_many :vocabulary_entries, dependent: :destroy
  has_many :suggestion_dismissals, dependent: :destroy
  has_many :meal_suggestions, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :notifications, dependent: :destroy

  validates :name, presence: true, length: { maximum: 60 }
  validates :uuid, :token, :join_code, presence: true, uniqueness: true
  validates :alerts_per_week, inclusion: { in: 0..Notification::MAX_PER_WEEK }
  validates :brotbox_count, numericality: { only_integer: true, in: BROTBOXEN }, allow_nil: true
  validates :diet, inclusion: { in: DIETS }, allow_nil: true
  validate :excluded_foods_fit

  before_validation :assign_identity, on: :create
  # Today's recipes were written for the old diet or list: they must not be
  # shown again after it changed (Recipes::Suggest stores one answer a day).
  after_update_commit :forget_todays_meals, if: -> { saved_change_to_diet? || saved_change_to_excluded_foods? }

  normalizes :name, with: ->(n) { n.to_s.strip.presence }
  # Stripped, blanks dropped, and "Nüsse" and "nüsse" kept once.
  normalizes :excluded_foods, with: ->(list) {
    Array(list).map { |food| food.to_s.strip }.reject(&:empty?).uniq(&:downcase)
  }

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

  # The kitchen's own clock: notifications go out at its dinner time, not ours.
  def local_now(at = Time.current)
    at.in_time_zone(ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone["Europe/Berlin"])
  end

  def touch_seen!
    update_column(:last_seen_at, Time.current) if last_seen_at.nil? || last_seen_at < 1.hour.ago
  end

  private

  def forget_todays_meals
    meal_suggestions.where(served_on: local_now.to_date - 1..).delete_all
  end

  def excluded_foods_fit
    list = Array(excluded_foods)
    errors.add(:excluded_foods, :too_long, count: MAX_EXCLUDED) if list.size > MAX_EXCLUDED
    return unless list.any? { |food| food.to_s.length > MAX_EXCLUDED_LENGTH }

    errors.add(:excluded_foods, :invalid)
  end

  def assign_identity
    self.uuid      ||= SecureRandom.uuid
    self.token     ||= SecureRandom.urlsafe_base64(32)
    self.join_code ||= self.class.generate_join_code
    self.name      ||= self.class.random_name
  end
end
