module Ai
  # One place for model choice and price, because "we picked the cheapest model"
  # is a claim that has to be checkable against an invoice.
  #
  # Prices are USD per 1M tokens, list price at time of writing. They are only
  # used to attribute cost to a capture — nothing behaves differently if they
  # drift — but keep them current, because the whole unit-economics case in
  # docs/13-mvp-cost-model.md is computed from this table.
  module Config
    Model = Struct.new(:name, :input_per_m, :output_per_m, :temperature, :token_param, keyword_init: true)

    MODELS = {
      # Reads a receipt end to end. Doc 12 measures ~$0.0024 for a 30-line German
      # Bon: enough headroom over gpt-5-nano's accuracy on faded thermal paper.
      "gpt-5-mini" => Model.new(name: "gpt-5-mini", input_per_m: 0.25, output_per_m: 2.00,
                                temperature: nil, token_param: "max_completion_tokens"),
      # Text-only work — turning "milk, broccoli, two chicken breasts" into rows.
      # 5x cheaper in, 5x cheaper out, and the task has no visual ambiguity.
      "gpt-5-nano" => Model.new(name: "gpt-5-nano", input_per_m: 0.05, output_per_m: 0.40,
                                temperature: nil, token_param: "max_completion_tokens"),
      "gpt-4o-mini" => Model.new(name: "gpt-4o-mini", input_per_m: 0.15, output_per_m: 0.60,
                                 temperature: 0, token_param: "max_tokens")
    }.freeze

    # Billed per minute of audio rather than per token.
    TRANSCRIBE_USD_PER_MINUTE = 0.003

    DEFAULTS = {
      receipt_extract: "gpt-5-mini",
      shelf_photo_extract: "gpt-5-mini",
      text_parse: "gpt-5-nano",
      memo_parse: "gpt-5-nano"
    }.freeze

    module_function

    def model_for(purpose)
      name = ENV["AI_MODEL_#{purpose.to_s.upcase}"].presence || DEFAULTS.fetch(purpose)
      MODELS.fetch(name) { raise ArgumentError, "unknown model #{name.inspect}; add it to Ai::Config::MODELS" }
    end

    def transcribe_model = ENV.fetch("AI_MODEL_TRANSCRIBE", "gpt-4o-mini-transcribe")

    def api_key = ENV["OPENAI_API_KEY"].presence

    def base_url = ENV.fetch("OPENAI_BASE_URL", "https://api.openai.com/v1")

    # auto: live when a key is configured, stub otherwise. A stub keeps the whole
    # app clickable with no key and no spend, which is how the UI gets built.
    def mode
      configured = ENV.fetch("AI_MODE", "auto")
      return configured if %w[live stub].include?(configured)

      api_key ? "live" : "stub"
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
