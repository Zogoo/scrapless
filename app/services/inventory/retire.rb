module Inventory
  # Forgets, the way a person forgets.
  #
  # The single most important mechanic in the product (doc 2 §2.4): stale guesses
  # remove themselves. The user is never handed a cleanup list, because a cleanup
  # list is the chore that killed every app in the category.
  class Retire < ApplicationService
    GHOST_ELAPSED = 1.3
    GHOST_PRESENCE = 0.2

    def initialize(household:, on: Date.current)
      @household = household
      @on = on
    end

    def call
      retired = @household.items.active.select { |item| ghost?(item) }
      retired.each do |item|
        item.update!(state: "retired", resolved_at: Time.current)
        item.item_events.create!(household: @household, kind: "retired", at: Time.current,
                                 meta: { reason: "auto", life_fraction: item.life_fraction(@on) }.to_json)
      end
      retired
    end

    private

    def ghost?(item)
      return false if item.frozen_storage?
      return false if item.snoozed_until.present? && item.snoozed_until >= @on

      item.life_fraction(@on) > GHOST_ELAPSED &&
        Freshness::PresenceModel.call(item: item, on: @on) < GHOST_PRESENCE
    end
  end
end
