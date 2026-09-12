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

    # The provider is refusing, not the photo. Quota, auth, a 5xx or a dead
    # socket: retaking the picture cannot fix any of them, so the UI must say
    # something different and point at the paths that still work.
    class Unavailable < Error; end
    class MissingKey < Unavailable; end

    TIMEOUT = 60

    def initialize(household: nil, provider: Config.provider, attempt: 0)
      @household = household
      @provider = provider
      @attempt = attempt
    end

    attr_reader :provider

    # Returns the parsed JSON object the model produced.
    def json_completion(purpose:, messages:, schema:, max_output_tokens: 2000)
      model = Config.model_for(purpose, provider: @provider)
      body = {
        model: model.name,
        messages: messages_for(messages, schema)
      }.merge(response_format_for(schema))
      body[:temperature] = model.temperature unless model.temperature.nil?
      body[:reasoning_effort] = model.reasoning if model.reasoning.present?
      # Reasoning models spend this budget on thinking before they write, so the
      # headroom is not generosity — it is the difference between an answer and
      # an empty string.
      body[model.token_param.to_sym] = model.reasoning.present? ? max_output_tokens * 3 : max_output_tokens

      started = monotonic_ms
      response = post_json("#{Config.base_url(provider: @provider)}/chat/completions", body)
      usage = response.fetch("usage", {})

      record_call(
        purpose: purpose, model: model.name,
        input_tokens: usage["prompt_tokens"].to_i, output_tokens: usage["completion_tokens"].to_i,
        cost_micros: Config.cost_micros(model.name, usage["prompt_tokens"].to_i, usage["completion_tokens"].to_i),
        duration_ms: monotonic_ms - started, success: true
      )

      content = response.dig("choices", 0, "message", "content")
      if content.blank?
        # Say which kind of empty. "empty completion" alone cost a diagnostic
        # round trip once already; finish_reason names the cause immediately.
        reason = response.dig("choices", 0, "finish_reason").presence || "unknown"
        raise Error, "empty completion (finish_reason=#{reason})"
      end

      JSON.parse(content)
    rescue Error, JSON::ParserError => e
      record_call(purpose: purpose, model: Config.model_for(purpose, provider: @provider).name,
                  success: false, error_message: e.message.truncate(200))
      raise
    end

    # Returns the transcript text.
    def transcribe(io:, filename:, content_type:, duration_seconds: 0.0)
      unless @provider.transcription
        raise Unavailable, "#{@provider.name} has no transcription endpoint"
      end

      started = monotonic_ms
      response = post_multipart(
        "#{Config.base_url(provider: @provider)}/audio/transcriptions",
        model: Config.transcribe_model(provider: @provider),
        io: io, filename: filename, content_type: content_type
      )

      record_call(
        purpose: :transcribe, model: Config.transcribe_model(provider: @provider),
        audio_seconds: duration_seconds,
        cost_micros: Config.transcribe_cost_micros(duration_seconds),
        duration_ms: monotonic_ms - started, success: true
      )

      response["text"].to_s
    rescue Error => e
      record_call(purpose: :transcribe, model: Config.transcribe_model(provider: @provider),
                  success: false, error_message: e.message.truncate(200))
      raise
    end

    private

    # Providers disagree about structured output, and this is the whole of the
    # disagreement.
    #
    # OpenAI accepts a strict JSON Schema and guarantees the shape. Gemini's
    # OpenAI-compatible layer accepts `response_format`, but its schema dialect
    # is an OpenAPI subset that rejects the `["string", "null"]` unions our
    # schemas are full of — and most local runners guarantee nothing beyond
    # "valid JSON". So those providers get `json_object` plus the schema in the
    # prompt, which models follow well in practice.
    def response_format_for(schema)
      if Config.structured_output(provider: @provider) == :json_schema
        { response_format: { type: "json_schema",
                             json_schema: { name: "extraction", strict: true, schema: schema } } }
      else
        { response_format: { type: "json_object" } }
      end
    end

    # Appends the very same schema constant to the system prompt. One source of
    # truth either way, so the two paths cannot drift into describing different
    # shapes — which would be an unusually annoying bug to find.
    def messages_for(messages, schema)
      return messages if Config.structured_output(provider: @provider) == :json_schema

      instruction = <<~TEXT
        Reply with JSON only — no prose, no markdown fence — matching this JSON Schema exactly.
        Where the schema allows null, use null rather than omitting the key.

        #{JSON.pretty_generate(schema)}
      TEXT

      index = messages.index { |m| m[:role].to_s == "system" }
      return messages + [ { role: "system", content: instruction } ] if index.nil?

      augmented = messages.dup
      original = augmented[index]
      augmented[index] = original.merge(content: "#{original[:content]}\n\n#{instruction}")
      augmented
    end

    def post_json(url, body)
      request = Net::HTTP::Post.new(URI(url))
      request["Content-Type"] = "application/json"
      request.body = body.to_json
      perform(request)
    end

    def post_multipart(url, model:, io:, filename:, content_type:)
      boundary = "----scrapless#{SecureRandom.hex(12)}"
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
      key = Config.api_key(provider: @provider)
      raise MissingKey, "#{@provider.key_env} is not set" if key.blank?

      request["Authorization"] = "Bearer #{key}"
      uri = request.uri

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise Unavailable, "#{response.code}: #{response.body.to_s.truncate(300)}"
      end

      JSON.parse(response.body)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      raise Unavailable, "transport: #{e.class}"
    end

    def record_call(purpose:, model:, input_tokens: 0, output_tokens: 0, audio_seconds: 0.0,
                    cost_micros: 0, duration_ms: 0, success: true, error_message: nil)
      AiCall.create!(
        household: @household, purpose: purpose.to_s, model: model,
        provider: @provider.name, attempt: @attempt,
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
