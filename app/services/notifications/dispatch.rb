module Notifications
  # One tick of the notification clock.
  #
  # The clock is an hourly Fly machine that POSTs /internal/notifications/tick,
  # because this machine sleeps when idle and a scheduler inside it would sleep
  # too. Each tick spends a slot for every kitchen that is in its dinner window
  # (doc 4 §4.9: 17:00 local), still has budget this week, has not been notified
  # today, and has something worth saying. Then each phone gets its own job, so
  # one phone's failure is retried without resending to the others.
  #
  # The window is three hours, so a late or missed tick still delivers; the
  # unique indexes on Notification make a repeated tick send nothing.
  class Dispatch < ApplicationService
    SEND_HOURS = 17...20

    def initialize(at: Time.current)
      @at = at
    end

    def call
      return [] unless Vapid.configured?

      Household.where(id: PushSubscription.select(:household_id))
               .where(alerts_per_week: 1..)
               .find_each.filter_map { |household| spend(household) }
    end

    private

    def spend(household)
      now = household.local_now(@at)
      return unless SEND_HOURS.cover?(now.hour)

      today = now.to_date
      week = Notification.week_of(today)
      spent = household.notifications.where(iso_week: week).count
      return if spent >= household.alerts_per_week || household.notifications.exists?(sent_on: today)

      picks = Compose.call(household: household, on: today)
      return if picks.empty?

      notification = household.notifications.create!(iso_week: week, slot: spent + 1, sent_on: today,
                                                     item_ids: picks.map { |scored| scored.item.id })
      household.push_subscriptions.ids.each { |id| DeliverPushJob.perform_later(notification.id, id) }
      notification
    rescue ActiveRecord::RecordNotUnique
      nil # another tick spent this slot first
    rescue StandardError => e
      # One kitchen's bad data must not cost every later kitchen its evening.
      Rails.error.report(e, context: { household_id: household.id })
      nil
    end
  end
end
