module Ai
  # Provider choice, model choice and price.
  #
  # There is more than one provider on purpose: a hard quota on the primary used
  # to take the whole capture path down with it (observed live — every receipt
  # returned 429 for an hour). A second provider turns that from an outage into
  # a slightly more expensive Tuesday.
  #
  # Prices are USD per 1M tokens, list price at time of writing. They only
  # attribute cost to a capture — nothing behaves differently if they drift — but
  # keep them current, because docs/14-mvp-cost-model.md is computed from them.
  module Config
    # `reasoning` is set for the gpt-5 family and matters more than it looks:
    # on those models the token budget covers *internal reasoning tokens too*,
    # they are billed as output, and if reasoning exhausts the budget the visible
    # content comes back empty. Observed live — a text parse burned all 1200
    # tokens reasoning and returned nothing, for $0.0005 and 7.7 seconds.
    #
    # Extraction is not a reasoning task, so these are pinned to minimal effort.
    Model = Struct.new(:name, :input_per_m, :output_per_m, :temperature, :token_param, :reasoning,
                       keyword_init: true)

    Provider = Struct.new(:name, :base_url, :key_env, :structured_output, :transcription, keyword_init: true)

    # Every provider here speaks the OpenAI /chat/completions wire format, which
    # is why adding one costs an environment variable rather than a rewrite.
    #
    # `structured_output` is the one thing they genuinely disagree on:
    #   :json_schema  — accepts a strict JSON Schema and guarantees the shape
    #   :json_object  — guarantees only "some JSON", so the schema goes in the
    #                   prompt instead (Ai::Client#messages_for)
    PROVIDERS = {
      "openai" => Provider.new(
        name: "openai",
        base_url: "https://api.openai.com/v1",
        key_env: "OPENAI_API_KEY",
        structured_output: :json_schema,
        transcription: true
      ),
      # Doc 12 §12.1 names Gemini Flash the cost-optimal reader, and it has a
      # free tier — which makes it a good second in the chain: when the primary
      # runs dry the fallback is cheaper, not more expensive.
      #
      # Its OpenAI layer accepts response_format, but its schema dialect is an
      # OpenAPI subset that rejects the ["string","null"] unions our schemas use,
      # so it takes the prompt-schema path. It has no /audio/transcriptions.
      "gemini" => Provider.new(
        name: "gemini",
        base_url: "https://generativelanguage.googleapis.com/v1beta/openai",
        key_env: "GEMINI_API_KEY",
        structured_output: :json_object,
        transcription: false
      ),
      # Free tier, fast, and unlike Gemini it does implement Whisper-shaped
      # transcription — the better fallback if voice on Safari matters.
      "groq" => Provider.new(
        name: "groq",
        base_url: "https://api.groq.com/openai/v1",
        key_env: "GROQ_API_KEY",
        structured_output: :json_object,
        transcription: true
      ),
      # Anything local speaking the OpenAI shape: Ollama, llama.cpp, LM Studio.
      # No key, no network, no bill — the last resort that cannot run out.
      "local" => Provider.new(
        name: "local",
        base_url: "http://localhost:11434/v1",
        key_env: "LOCAL_API_KEY",
        structured_output: :json_object,
        transcription: false
      )
    }.freeze

    MODELS = {
      # --- OpenAI ---
      # Reads a receipt end to end. Doc 12 measures ~$0.0024 for a 30-line German
      # Bon: enough headroom over the nano tier on faded thermal paper.
      "gpt-5-mini" => Model.new(name: "gpt-5-mini", input_per_m: 0.25, output_per_m: 2.00,
                                temperature: nil, token_param: "max_completion_tokens",
                                reasoning: "minimal"),
      "gpt-5-nano" => Model.new(name: "gpt-5-nano", input_per_m: 0.05, output_per_m: 0.40,
                                temperature: nil, token_param: "max_completion_tokens",
                                reasoning: "minimal"),
      "gpt-4o-mini" => Model.new(name: "gpt-4o-mini", input_per_m: 0.15, output_per_m: 0.60,
                                 temperature: 0, token_param: "max_tokens"),

      # --- Gemini ---
      # ⚠️ Prices follow doc 12's table. Google has repriced this tier before;
      # verify against current pricing before quoting these figures anywhere.
      "gemini-2.5-flash" => Model.new(name: "gemini-2.5-flash", input_per_m: 0.15, output_per_m: 0.60,
                                      temperature: 0, token_param: "max_tokens"),
      "gemini-2.5-flash-lite" => Model.new(name: "gemini-2.5-flash-lite", input_per_m: 0.10,
                                           output_per_m: 0.40, temperature: 0, token_param: "max_tokens"),
      "gemini-2.0-flash" => Model.new(name: "gemini-2.0-flash", input_per_m: 0.10, output_per_m: 0.40,
                                      temperature: 0, token_param: "max_tokens"),

      # --- Local / open weight. Marginal cost is zero; the GPU is the cost. ---
      "qwen2.5vl:7b" => Model.new(name: "qwen2.5vl:7b", input_per_m: 0.0, output_per_m: 0.0,
                                  temperature: 0, token_param: "max_tokens"),
      "llama3.2-vision" => Model.new(name: "llama3.2-vision", input_per_m: 0.0, output_per_m: 0.0,
                                     temperature: 0, token_param: "max_tokens")
    }.freeze

    TRANSCRIBE_USD_PER_MINUTE = 0.003

    DEFAULT_MODELS = {
      "openai" => { receipt_extract: "gpt-5-mini", shelf_photo_extract: "gpt-5-mini",
                    text_parse: "gpt-5-nano", memo_parse: "gpt-5-nano" },
      "gemini" => { receipt_extract: "gemini-2.5-flash", shelf_photo_extract: "gemini-2.5-flash",
                    text_parse: "gemini-2.5-flash-lite", memo_parse: "gemini-2.5-flash-lite" },
      "groq" => { receipt_extract: "gemini-2.5-flash", shelf_photo_extract: "gemini-2.5-flash",
                  text_parse: "gemini-2.5-flash-lite", memo_parse: "gemini-2.5-flash-lite" },
      "local" => { receipt_extract: "qwen2.5vl:7b", shelf_photo_extract: "qwen2.5vl:7b",
                   text_parse: "qwen2.5vl:7b", memo_parse: "qwen2.5vl:7b" }
    }.freeze

    DEFAULT_TRANSCRIBE = { "openai" => "gpt-4o-mini-transcribe", "groq" => "whisper-large-v3-turbo" }.freeze

    # Tried in order. Explicit AI_PROVIDERS wins; otherwise every provider with a
    # key configured, primary first.
    FALLBACK_ORDER = %w[openai gemini groq local].freeze

    module_function

    def chain
      names = ENV["AI_PROVIDERS"].presence&.split(",")&.map(&:strip)
      names ||= [ ENV["AI_PROVIDER"].presence ].compact.presence
      names ||= FALLBACK_ORDER.select { |n| configured?(PROVIDERS.fetch(n)) }

      providers = names.map { |n| PROVIDERS.fetch(n) { raise ArgumentError, "unknown provider #{n.inspect}" } }
      providers.presence || [ PROVIDERS.fetch("openai") ]
    end

    # The head of the chain — what a single call uses when nothing goes wrong.
    def provider = chain.first

    # Strictly "has a credential in the environment".
    #
    # Note what is deliberately absent: `local` is never auto-detected. It has no
    # key to check, so treating it as always-configured would put it in every
    # chain — and an install with no keys at all would come up "live", try
    # localhost:11434, and fail, instead of falling back to the stub that keeps
    # the app clickable. Local is opt-in via AI_PROVIDER(S) only.
    def configured?(provider) = ENV[provider.key_env].present?

    def model_for(purpose, provider: self.provider)
      name = ENV["AI_MODEL_#{purpose.to_s.upcase}_#{provider.name.upcase}"].presence ||
             ENV["AI_MODEL_#{purpose.to_s.upcase}"].presence ||
             DEFAULT_MODELS.fetch(provider.name, DEFAULT_MODELS["openai"]).fetch(purpose)
      MODELS.fetch(name) { raise ArgumentError, "unknown model #{name.inspect}; add it to Ai::Config::MODELS" }
    end

    def transcribe_model(provider: self.provider)
      ENV["AI_MODEL_TRANSCRIBE"].presence || DEFAULT_TRANSCRIBE.fetch(provider.name, "gpt-4o-mini-transcribe")
    end

    def api_key(provider: self.provider)
      ENV[provider.key_env].presence || (provider.name == "local" ? "local" : nil)
    end

    def base_url(provider: self.provider)
      ENV["AI_BASE_URL_#{provider.name.upcase}"].presence ||
        ENV["OPENAI_BASE_URL"].presence ||
        provider.base_url
    end

    def structured_output(provider: self.provider) = provider.structured_output

    # auto: live when some provider in the chain has a key, stub otherwise. The
    # stub keeps the whole app clickable with no key and no spend.
    def mode
      configured = ENV.fetch("AI_MODE", "auto")
      return configured if %w[live stub].include?(configured)

      chain.any? { |p| configured?(p) } ? "live" : "stub"
    end

    def live? = mode == "live"

    def cost_micros(model_name, input_tokens, output_tokens)
      model = MODELS[model_name]
      return 0 if model.nil?

      usd = (input_tokens / 1_000_000.0 * model.input_per_m) +
            (output_tokens / 1_000_000.0 * model.output_per_m)
      (usd * 1_000_000).round
    end

    def transcribe_cost_micros(seconds)
      ((seconds / 60.0) * TRANSCRIBE_USD_PER_MINUTE * 1_000_000).round
    end
  end
end
