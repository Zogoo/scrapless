module Api
  module V1
    # What the AI has actually cost.
    #
    # Exposed in the product rather than buried in a dashboard because the
    # unit-economics case for this MVP is "a capture costs a fraction of a cent",
    # and a claim like that should be falsifiable by anyone using it.
    class CostsController < ApplicationController
      def show
        calls = AiCall.all
        render json: {
          mode: Ai::Config.mode,
          chain: Ai::Config.chain.map(&:name),
          models: chain_models,
          transcribe_usd_per_minute: Ai::Config::TRANSCRIBE_USD_PER_MINUTE,
          totals: totals(calls),
          by_purpose: calls.group(:purpose).pluck(
            Arel.sql("purpose, COUNT(*), SUM(cost_micros), AVG(duration_ms)")
          ).map { |purpose, count, micros, avg_ms|
            { purpose: purpose, calls: count, usd: usd(micros), avg_ms: avg_ms.to_i,
              usd_per_call: count.positive? ? usd(micros.to_f / count) : 0.0 }
          },
          by_provider: by_provider(calls),
          fallbacks: calls.where("attempt > 0").count,
          this_fridge: totals(AiCall.where(household: current_household))
        }
      end

      private

      # What each job is pointed at, per provider in the chain — so a reader can
      # see both what is being used now and what it would fall back to.
      def chain_models
        Ai::Config.chain.to_h do |provider|
          models = Ai::Config::DEFAULT_MODELS.fetch(provider.name, {}).keys.to_h do |purpose|
            [ purpose, model_row(Ai::Config.model_for(purpose, provider: provider).name) ]
          end
          [ provider.name, models ]
        end
      end

      # A fallback is only visible if the ledger says who served each call.
      def by_provider(calls)
        calls.group(:provider).pluck(
          Arel.sql("provider, COUNT(*), SUM(cost_micros), SUM(CASE WHEN success THEN 0 ELSE 1 END)")
        ).map do |provider, count, micros, failures|
          { provider: provider, calls: count, usd: usd(micros), failures: failures }
        end
      end

      def model_row(name)
        model = Ai::Config::MODELS[name]
        { name: name, input_usd_per_m: model&.input_per_m, output_usd_per_m: model&.output_per_m }
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
