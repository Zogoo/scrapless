module Notifications
  # The words on the lock screen, in the phone's language.
  #
  # Built at delivery, not at dispatch, so a food used up in between is left
  # out — and if nothing is left, nothing is sent. High-risk food is never
  # "use it tonight", only "worth checking" (doc 4 §4.13; Copy.headline does the
  # same on Today).
  #
  # The bell shows the same words later, so it passes the foods it found itself:
  # what was said stays readable after the food is gone.
  class Message < ApplicationService
    TAG = "scrapless-rescue" # one at a time: a newer notification replaces an older one

    def self.url_for(notification) = "/today?n=#{notification.id}"

    def initialize(notification:, locale:, items: nil)
      @notification = notification
      @locale = locale
      @items = items
    end

    def call
      items = @items || still_here
      return if items.empty?

      I18n.with_locale(@locale) do
        { title: I18n.t("notifications.title"), body: body(items), tag: TAG,
          url: self.class.url_for(@notification) }
      end
    end

    private

    # In the order Compose ranked them.
    def still_here
      found = @notification.items.active.index_by(&:id)
      @notification.item_ids.filter_map { |id| found[id] }
    end

    def body(items)
      names = items.map { |item| Copy.bare_name(item) }
      names = names.one? ? names.first : I18n.t("notifications.and", first: names.first, second: names.last)
      return I18n.t("notifications.check", names: names) if items.any?(&:high_risk?)

      I18n.t("notifications.use", names: names, count: items.size)
    end
  end
end
