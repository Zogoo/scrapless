module Freshness
  # Ranks what to worry about tonight.
  #
  # risk = P(still present) x P(gone off)
  #
  # Multiplying is the whole point. Spoilage alone recommends the food most
  # likely to already be eaten; presence alone recommends whatever was bought
  # longest ago. Neither is useful by itself, and the first one is how this
  # category earns its reputation for crying wolf.
  class RiskScorer < ApplicationService
    # Worth putting on the Today screen at all.
    RISK_FLOOR = 0.12
    # Worth spending one of the three weekly notifications on — a higher bar,
    # because an interruption costs more than a line in a list.
    SPOILAGE_FLOOR = 0.4

    Scored = Struct.new(:item, :presence, :spoilage, :risk, :days_left, :phase, keyword_init: true) do
      def worth_showing? = risk >= RISK_FLOOR

      def alertable?
        presence >= PresenceModel::ALERT_FLOOR && spoilage >= SPOILAGE_FLOOR
      end

      # Only ask about it in the sweep if we are unsure *and* the answer changes
      # something. Asking is a cost paid from the weekly effort budget.
      def ambiguous?
        PresenceModel::AMBIGUOUS_BAND.cover?(presence) && item.life_fraction >= 0.5
      end
    end

    def initialize(items:, on: Date.current)
      @items = items
      @on = on
    end

    def call
      @items.map { |item| score(item) }.sort_by { |s| [ -s.risk, s.days_left ] }
    end

    private

    def score(item)
      presence = PresenceModel.call(item: item, on: @on)
      spoilage = spoilage_probability(item)

      Scored.new(
        item: item,
        presence: presence,
        spoilage: spoilage,
        risk: (presence * spoilage).round(3),
        days_left: item.days_left(@on),
        phase: phase_for(item)
      )
    end

    # Zero until the uncertainty band opens, one at the far end of it. The band
    # is the estimate; the ramp inside it is the honest reading of "we think it
    # goes off somewhere in here". Slightly convex so the front of the band is
    # quiet — that is where a false alarm is most expensive.
    def spoilage_probability(item)
      band = (item.window_end - item.window_start).to_i
      return (@on >= item.window_end ? 1.0 : 0.0) if band <= 0

      position = (@on - item.window_start).to_i / band.to_f
      return 0.0 if position <= 0

      (position**1.4).clamp(0.0, 1.0).round(3)
    end

    def phase_for(item)
      case item.life_fraction(@on)
      when 0...0.5 then "fresh"
      when 0.5...0.8 then "aging"
      when 0.8...1.3 then "at_risk"
      else "ghost"
      end
    end
  end
end
