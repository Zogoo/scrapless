require "net/http"
require "uri"
require "securerandom"

module Ai
  # Thin OpenAI transport. Deliberately Net::HTTP rather than a vendor SDK: two
  # endpoints are used in total, and an SDK here would be a dependency to upgrade
  # forever in exchange for nothing.
  #
  # Every call writes an AiCall row whether it succeeds or fails, so the cost
  # dashboard cannot silently under-report.
  class Client
    class Error < StandardError; end
    class MissingKey < Error; end

    TIMEOUT = 60

    def initialize(household: nil)
      @household = household
    end

    # Returns the parsed JSON object the model produced.
    def json_completion(purpose:, messages:, schema:, max_output_tokens: 2000)
      model = Config.model_for(purpose)
      body = {
        model: model.name,
        messages: messages,
        response_format: { type: "json_schema", json_schema: { name: "extraction", strict: true, schema: schema } }
      }
      body[:temperature] = model.temperature unless model.temperature.nil?
      body[model.token_param.to_sym] = max_output_tokens

      started = monotonic_ms
      response = post_json("#{Config.base_url}/chat/completions", body)
      usage = response.fetch("usage", {})

      record_call(
        purpose: purpose, model: model.name,
        input_tokens: usage["prompt_tokens"].to_i, output_tokens: usage["completion_tokens"].to_i,
        cost_micros: Config.cost_micros(model.name, usage["prompt_tokens"].to_i, usage["completion_tokens"].to_i),
        duration_ms: monotonic_ms - started, success: true
      )

      content = response.dig("choices", 0, "message", "content")
      raise Error, "empty completion" if content.blank?

      JSON.parse(content)
    rescue Error, JSON::ParserError => e
      record_call(purpose: purpose, model: Config.model_for(purpose).name, success: false,
                  error_message: e.message.truncate(200))
      raise
    end

    # Returns the transcript text.
    def transcribe(io:, filename:, content_type:, duration_seconds: 0.0)
      started = monotonic_ms
      response = post_multipart(
        "#{Config.base_url}/audio/transcriptions",
        model: Config.transcribe_model, io: io, filename: filename, content_type: content_type
      )

      record_call(
        purpose: :transcribe, model: Config.transcribe_model,
        audio_seconds: duration_seconds,
        cost_micros: Config.transcribe_cost_micros(duration_seconds),
        duration_ms: monotonic_ms - started, success: true
      )

      response["text"].to_s
    rescue Error => e
      record_call(purpose: :transcribe, model: Config.transcribe_model, success: false,
                  error_message: e.message.truncate(200))
      raise
    end

    private

    def post_json(url, body)
      request = Net::HTTP::Post.new(URI(url))
      request["Content-Type"] = "application/json"
      request.body = body.to_json
      perform(request)
    end

    def post_multipart(url, model:, io:, filename:, content_type:)
      boundary = "----crisper#{SecureRandom.hex(12)}"
      payload = +""
      payload << "--#{boundary}\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n#{model}\r\n"
      payload << "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
      payload << "Content-Type: #{content_type}\r\n\r\n"
      payload << io.read.dup.force_encoding(Encoding::BINARY)
      payload << "\r\n--#{boundary}--\r\n"

      request = Net::HTTP::Post.new(URI(url))
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = payload
      perform(request)
    end

    def perform(request)
      key = Config.api_key
      raise MissingKey, "OPENAI_API_KEY is not set" if key.blank?

      request["Authorization"] = "Bearer #{key}"
      uri = request.uri

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "#{response.code}: #{response.body.to_s.truncate(300)}"
      end

      JSON.parse(response.body)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      raise Error, "transport: #{e.class}"
    end

    def record_call(purpose:, model:, input_tokens: 0, output_tokens: 0, audio_seconds: 0.0,
                    cost_micros: 0, duration_ms: 0, success: true, error_message: nil)
      AiCall.create!(
        household: @household, purpose: purpose.to_s, model: model,
        input_tokens: input_tokens, output_tokens: output_tokens, audio_seconds: audio_seconds,
        cost_micros: cost_micros, duration_ms: duration_ms,
        success: success, error_message: error_message
      )
    rescue StandardError => e
      Rails.logger.warn("failed to record AiCall: #{e.message}")
    end

    def monotonic_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  end
end
