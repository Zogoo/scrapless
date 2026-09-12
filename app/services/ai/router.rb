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

    def initialize(household: nil)
      @household = household
    end

    def json_completion(purpose:, messages:, schema:, max_output_tokens: 2000)
      attempt(:json_completion) do |client|
        client.json_completion(purpose: purpose, messages: messages, schema: schema,
                               max_output_tokens: max_output_tokens)
      end
    end

    def transcribe(io:, filename:, content_type:, duration_seconds: 0.0)
      # Rewound per attempt: a failed upload has already consumed the stream, and
      # the next provider would otherwise be handed zero bytes.
      attempt(:transcribe, require_transcription: true) do |client|
        io.rewind if io.respond_to?(:rewind)
        client.transcribe(io: io, filename: filename, content_type: content_type,
                          duration_seconds: duration_seconds)
      end
    end

    private

    def attempt(job, require_transcription: false)
      candidates = Config.chain
      candidates = candidates.select(&:transcription) if require_transcription
      raise NoProviderAvailable, "no provider can #{job}" if candidates.empty?

      last_error = nil

      candidates.each_with_index do |provider, index|
        client = Client.new(household: @household, provider: provider, attempt: index)
        return yield(client)
      rescue Client::Unavailable => e
        last_error = e
        Rails.logger.warn("ai: #{provider.name} unavailable for #{job} (#{e.message.truncate(120)})")
        next
      end

      raise last_error || NoProviderAvailable.new("no provider could #{job}")
    end
  end
end
