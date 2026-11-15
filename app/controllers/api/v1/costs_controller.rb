module Api
  module V1
    # What the AI has cost this kitchen.
    #
    # Exposed in the product because the unit-economics case for this MVP is "a
    # capture costs a fraction of a cent", and a claim like that should be
    # checkable by whoever is paying. Scoped to the asking kitchen: the global
    # ledger, provider chain and model table are operator data, and a fridge is
    # free for anyone to make.
    class CostsController < ApplicationController
      def show
        calls = AiCall.where(household: current_household)
        render json: {
          mode: Ai::Config.mode,
          transcribe_usd_per_minute: Ai::Config::TRANSCRIBE_USD_PER_MINUTE,
          totals: totals(calls),
          by_purpose: by_purpose(calls)
        }
      end

      private

      # Per call is per *successful* call: a refused read costs nothing and
      # produced nothing, so counting it would make a receipt look cheaper.
      def by_purpose(calls)
        calls.group(:purpose).pluck(
          Arel.sql("purpose, COUNT(*), SUM(CASE WHEN success THEN 1 ELSE 0 END), SUM(cost_micros), AVG(duration_ms)")
        ).map do |purpose, count, succeeded, micros, avg_ms|
          { purpose: purpose, calls: count, usd: usd(micros), avg_ms: avg_ms.to_i,
            usd_per_call: succeeded.positive? ? usd(micros.to_f / succeeded) : 0.0 }
        end
      end

      def totals(scope)
        {
          calls: scope.count,
          failures: scope.where(success: false).count,
          usd: usd(scope.sum(:cost_micros)),
          input_tokens: scope.sum(:input_tokens),
          output_tokens: scope.sum(:output_tokens)
        }
      end

      def usd(micros) = (micros.to_f / 1_000_000).round(6)
    end
  end
end
