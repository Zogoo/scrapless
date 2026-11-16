module Notifications
  # The words on the lock screen, in the phone's language.
  #
  # Built at delivery, not at dispatch, so a food used up in between is left
  # out — and if nothing is left, nothing is sent. High-risk food is never
  # "use it tonight", only "worth checking" (doc 4 §4.13; Copy.headline does the
  # same on Today).
  class Message < ApplicationService
    TAG = "scrapless-rescue" # one at a time: a newer notification replaces an older one

    def initialize(notification:, locale:)
      @notification = notification
      @locale = locale
    end

    def call
      items = still_here
      return if items.empty?

      I18n.with_locale(@locale) do
        { title: I18n.t("notifications.title"), body: body(items), tag: TAG,
          url: "/today?n=#{@notification.id}" }
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
