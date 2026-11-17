module Notifications
  # Sends one notification to one phone.
  #
  # A push service that is down, slow or rate-limiting gets retried by Active
  # Job with backoff; Solid Queue keeps the retry in SQLite, so it survives the
  # machine stopping and runs on the next wake. A phone that unsubscribed or
  # uninstalled (404/410) is forgotten. Anything else — a VAPID key that does not
  # match, a payload that is too large — fails loudly in solid_queue_failed_executions
  # rather than quietly deleting every subscription.
  class DeliverPushJob < ApplicationJob
    queue_as :default

    # A "tonight" notification that arrives tomorrow morning is noise.
    TTL = 3.hours
    TIMEOUT = 10

    retry_on WebPush::PushServiceError, WebPush::TooManyRequests,
             Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError,
             Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
             wait: :polynomially_longer, attempts: 5

    def perform(notification_id, subscription_id)
      subscription = PushSubscription.find_by(id: subscription_id)
      # Scoped through the phone's kitchen: a phone that has since joined another
      # kitchen is not told about the old one's food.
      notification = subscription&.household&.notifications&.find_by(id: notification_id)
      return unless notification && tonight?(notification)

      payload = Message.call(notification: notification, locale: subscription.locale)
      return unless payload

      # The number on the app icon (navigator.setAppBadge), counted as the bell does.
      send_push(subscription, payload.merge(unread: Inbox.unread(household: notification.household)))
      subscription.touch(:last_delivered_at)
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      subscription.destroy
    end

    private

    def tonight?(notification)
      notification.sent_on == notification.household.local_now.to_date
    end

    def send_push(subscription, payload)
      WebPush.payload_send(
        message: payload.to_json,
        endpoint: subscription.endpoint, p256dh: subscription.p256dh, auth: subscription.auth,
        vapid: Vapid.details, ttl: TTL.to_i, urgency: "normal",
        open_timeout: TIMEOUT, read_timeout: TIMEOUT
      )
    end
  end
end
