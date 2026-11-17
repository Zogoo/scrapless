module Notifications
  # What, if anything, is worth interrupting this kitchen for tonight.
  #
  # The bar is RiskScorer's `alertable?`: P(still present) x spoilage, never
  # spoilage alone, so a notification is not spent on food that is most likely
  # already eaten (doc 5 §5.4). Food someone said "not now" to stays quiet until
  # the snooze ends. At most two foods: one decision, one tap (doc 2 §2.9).
  #
  # An empty answer is the designed happy path — silence costs nothing and does
  # not use up the week's budget.
  class Compose < ApplicationService
    MAX_ITEMS = 2

    def initialize(household:, on: Date.current)
      @household = household
      @on = on
    end

    def call
      Inventory::Retire.call(household: @household, on: @on)
      items = @household.items.active.where("snoozed_until IS NULL OR snoozed_until < ?", @on).to_a
      Freshness::RiskScorer.call(items: items, on: @on).select(&:alertable?).first(MAX_ITEMS)
    end
  end
end
