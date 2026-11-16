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
  #
  # Every kitchen gets the notification, push or not: it always lands in the
  # bell, and push is only how it also reaches a lock screen. Without that, a
  # phone that never allowed push (or an iPhone not on the Home Screen) would
  # have no way to hear about the food at all (doc 4 §4.9).
  class Dispatch < ApplicationService
    SEND_HOURS = 17...20
    # The budget looks at one week and the bell at two; older rows are dead weight.
    KEEP = 60.days

    def initialize(at: Time.current)
      @at = at
    end

    def call
      Notification.where(sent_on: ...(@at.to_date - KEEP)).delete_all

      Household.where(alerts_per_week: 1..).find_each.filter_map { |household| spend(household) }
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
      push(notification, household)
      notification
    rescue ActiveRecord::RecordNotUnique
      nil # another tick spent this slot first
    rescue StandardError => e
      # One kitchen's bad data must not cost every later kitchen its evening.
      Rails.error.report(e, context: { household_id: household.id })
      nil
    end

    def push(notification, household)
      return unless Vapid.configured?

      household.push_subscriptions.ids.each { |id| DeliverPushJob.perform_later(notification.id, id) }
    end
  end
end
