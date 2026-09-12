module Ai
  # A hard ceiling on what the model calls may cost in a day.
  #
  # This exists because of the shape of the product, not because of paranoia:
  # there is no account wall, a fridge costs nothing to create, and the capture
  # endpoint is the most expensive thing in the system. Doc 5 §5.6 names the
  # consequence — "anyone could use Scrapless as a free receipt-OCR API". The
  # per-fridge rate limit does not help, because fridges are free to make.
  #
  # Counted out of the ai_calls ledger rather than a cache counter, so a restart
  # or a cache flush cannot quietly reset a spending limit.
  class Budget
    DEFAULT_DAILY_USD = 2.0

    class << self
      def daily_limit_usd
        ENV.fetch("AI_DAILY_BUDGET_USD", DEFAULT_DAILY_USD).to_f
      end

      def spent_today_usd
        AiCall.where(created_at: Time.current.beginning_of_day..).sum(:cost_micros) / 1_000_000.0
      end

      def exceeded?
        return false if daily_limit_usd <= 0 # 0 disables the ceiling entirely

        spent_today_usd >= daily_limit_usd
      end

      def remaining_usd = [ daily_limit_usd - spent_today_usd, 0.0 ].max
    end
  end
end
