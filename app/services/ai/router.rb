module Ai
  # Walks the provider chain.
  #
  # Exists because a hard quota on the primary used to take the whole capture
  # path down with it — every receipt returned 429 until somebody noticed and
  # topped up an account. With a chain, that becomes a fallback to a cheaper
  # provider and a line in the ledger.
  #
  # Only Unavailable triggers a fallback, and that is the point of the
  # distinction drawn in Ai::Client: Unavailable means the provider refused
  # (quota, credentials, outage, dead socket), which the next provider may well
  # not. A plain Error means the model answered and the answer was unusable —
  # paying a second provider to produce the same nonsense is just a second bill.
  class Router
    class NoProviderAvailable < Client::Unavailable; end

    # Deliberately an Unavailable: the app already degrades gracefully from one
    # of those — it stops offering the camera and points at the typed and spoken
    # paths, which cost nothing and keep working.
    class BudgetExceeded < Client::Unavailable; end

    # The caller's deadline ran out before every provider was tried.
    class DeadlinePassed < Client::TimedOut; end

    def initialize(household: nil)
      @household = household
    end

    # `timeout` (seconds) is one deadline for the whole chain, not one per
    # provider: a person waiting at the mic must not wait once per fallback.
    def json_completion(purpose:, messages:, schema:, max_output_tokens: 2000, timeout: nil)
      deadline = timeout && (monotonic + timeout)
      attempt(:json_completion, deadline: deadline) do |client, remaining|
        client.json_completion(purpose: purpose, messages: messages, schema: schema,
                               max_output_tokens: max_output_tokens, timeout: remaining || Client::TIMEOUT)
      end
    end

    def transcribe(io:, filename:, content_type:, duration_seconds: 0.0, language: nil, prompt: nil)
      # Rewound per attempt: a failed upload has already consumed the stream, and
      # the next provider would otherwise be handed zero bytes.
      attempt(:transcribe, require_transcription: true) do |client|
        io.rewind if io.respond_to?(:rewind)
        client.transcribe(io: io, filename: filename, content_type: content_type,
                          duration_seconds: duration_seconds, language: language, prompt: prompt)
      end
    end

    private

    def attempt(job, require_transcription: false, deadline: nil)
      if Budget.exceeded?
        raise BudgetExceeded, "daily AI budget of $#{Budget.daily_limit_usd} reached"
      end

      candidates = Config.chain
      candidates = candidates.select(&:transcription) if require_transcription
      raise NoProviderAvailable, "no provider can #{job}" if candidates.empty?

      last_error = nil

      candidates.each_with_index do |provider, index|
        remaining = deadline && (deadline - monotonic)
        if remaining && remaining <= 0
          last_error = DeadlinePassed.new("deadline passed before #{provider.name} was tried")
          break
        end

        client = Client.new(household: @household, provider: provider, attempt: index)
        return yield(client, remaining)
      rescue Client::Unavailable => e
        last_error = e
        Rails.logger.warn("ai: #{provider.name} unavailable for #{job} (#{e.message.truncate(120)})")
        next
      end

      raise last_error || NoProviderAvailable.new("no provider could #{job}")
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
