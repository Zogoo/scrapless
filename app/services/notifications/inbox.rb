module Notifications
  # What the bell shows: this kitchen's notifications from the last two weeks,
  # newest first, whether or not any phone got them as a push.
  #
  # Read is per kitchen — the food is shared, so once anyone has looked, the
  # kitchen knows. A notification counts as unread only while some of its food
  # is still here: the badge points at food to use, never at food already gone
  # (doc 4 §4.9 forbids the guilt counter). With the weekly budget at most three,
  # the badge cannot climb past that.
  class Inbox < ApplicationService
    DAYS = 14

    def initialize(household:, locale: I18n.locale)
      @household = household
      @locale = locale
    end

    def call
      notifications = @household.notifications
                                .where(sent_on: (@household.local_now.to_date - (DAYS - 1))..)
                                .order(sent_on: :desc).to_a
      foods = @household.items.where(id: notifications.flat_map(&:item_ids)).index_by(&:id)

      notifications.filter_map { |notification| entry(notification, foods) }
    end

    def self.unread(household:) = call(household: household).count { |entry| entry[:unread] }

    private

    def entry(notification, foods)
      items = notification.item_ids.filter_map { |id| foods[id] }
      message = Message.call(notification: notification, locale: @locale, items: items)
      return unless message # every food it named has been deleted since

      live = items.any? { |item| item.state == "active" }
      read = notification.opened_at.present?
      { id: notification.id, title: message[:title], body: message[:body], url: message[:url],
        sent_on: notification.sent_on, item_ids: items.map(&:id),
        read: read, live: live, unread: live && !read }
    end
  end
end
