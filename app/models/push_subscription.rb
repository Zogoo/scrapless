# A phone that said yes to notifications.
#
# The server POSTs to `endpoint`, so the endpoint is the one value here that
# could aim our own server at an address of the client's choosing (SSRF). Only
# the browsers' push services are accepted, over https.
class PushSubscription < ApplicationRecord
  MAX_PER_HOUSEHOLD = 10

  # The push services Chrome/Android/Samsung (FCM), Firefox, Safari and Edge
  # hand out. A browser on any other service simply cannot subscribe.
  PUSH_HOSTS = %w[fcm.googleapis.com updates.push.services.mozilla.com web.push.apple.com].freeze
  PUSH_HOST_SUFFIXES = %w[.push.apple.com .notify.windows.com].freeze

  # RFC 8291 keys arrive base64url-encoded: p256dh is 87 characters, auth 22.
  KEY_FORMAT = /\A[A-Za-z0-9_-]+={0,2}\z/

  belongs_to :household

  validates :endpoint, presence: true, length: { maximum: 1_000 }, uniqueness: true
  validates :p256dh, :auth, presence: true, length: { maximum: 200 }, format: { with: KEY_FORMAT }
  validates :locale, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } }
  validate :endpoint_is_a_push_service
  validate :within_household_limit, if: -> { new_record? || household_id_changed? }

  # Upserts by endpoint, so a phone that switched kitchens takes its
  # subscription with it instead of being notified about the old fridge.
  def self.register!(household:, endpoint:, p256dh:, auth:, locale:)
    find_or_initialize_by(endpoint: endpoint.to_s).tap do |subscription|
      subscription.update!(household: household, p256dh: p256dh, auth: auth, locale: locale)
    end
  end

  def self.push_host?(host)
    host = host.to_s.downcase
    PUSH_HOSTS.include?(host) || PUSH_HOST_SUFFIXES.any? { |suffix| host.end_with?(suffix) }
  end

  private

  def endpoint_is_a_push_service
    uri = URI.parse(endpoint.to_s)
    errors.add(:endpoint, :invalid) unless uri.is_a?(URI::HTTPS) && uri.userinfo.nil? &&
                                           uri.port == 443 && self.class.push_host?(uri.host)
  rescue URI::InvalidURIError
    errors.add(:endpoint, :invalid)
  end

  def within_household_limit
    return unless household
    return if household.push_subscriptions.where.not(id: id).count < MAX_PER_HOUSEHOLD

    errors.add(:household, :too_many_phones, message: "has too many phones subscribed")
  end
end
