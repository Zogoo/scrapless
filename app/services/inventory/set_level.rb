module Inventory
  # "How much milk is there?" — answered with one slider, no units.
  #
  # Two cartons bought on different days are two rows, on purpose: each keeps its
  # own window, and the presence model learns the household's buying cadence from
  # those separate acquired_on dates. The Kitchen shows them as one line, and this
  # turns that line's single level (0..packs) back into per-pack amounts.
  #
  # The level fills oldest-added first (lowest id). Lowering it therefore
  # drains the most recently added pack, and raising it refills that same pack
  # before any older one. A pack drained to nothing is resolved as used, the
  # same as tapping Used, and does not come back onto the line.
  #
  # Display only: amount_left does not feed Freshness::PresenceModel. Halving
  # presence is still the job of the partial_use event.
  class SetLevel < ApplicationService
    STEP = 0.05

    def initialize(household:, ids:, level:)
      @household = household
      @ids = Array(ids)
      @level = level.to_f
    end

    def call
      packs = @household.items.active.where(id: @ids).order(:id).to_a
      return packs if packs.empty?

      remaining = (@level.clamp(0, packs.size) / STEP).round * STEP

      Item.transaction do
        packs.each do |pack|
          amount = [ remaining, 1.0 ].min.round(2)
          remaining -= amount
          apply(pack, amount)
        end
      end

      packs.select { |pack| pack.state == "active" }
    end

    private

    def apply(pack, amount)
      if amount <= 0
        pack.update!(amount_left: 0, state: "rescued", resolved_at: Time.current)
        log(pack, "used", source: "level")
      elsif amount != pack.amount_left
        log(pack, "level_set", from: pack.amount_left, to: amount)
        pack.update!(amount_left: amount)
      end
    end

    def log(pack, kind, meta)
      pack.item_events.create!(household: @household, kind: kind, at: Time.current, meta: meta.to_json)
    end
  end
end
