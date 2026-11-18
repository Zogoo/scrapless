module Memo
  # One dictated sentence -> memo lines. Segmenter first, a model only when the
  # segmenter could not place every word (doc 15 §15.11).
  #
  # Who does what, and when — on every dictation, our server, nobody else:
  #
  # 1. Text::Segmenter splits the sentence with this kitchen's lexicon. Free.
  # 2. Sure (every line is a known item): its lines are used. No model call.
  # 3. Not sure, and AI is live: the model reads the sentence, within TIMEOUT.
  #    Its lines are used if every name is made of words that were said.
  # 4. Anything else — AI off, budget spent, provider down, too slow, invalid
  #    or ungrounded answer: the segmenter's lines are used, as said. Nothing
  #    is lost, and nobody is asked to fix anything.
  #
  # Every result says which path produced it (`path`) and why (`reason`), and
  # the controller logs both, so how often the model is needed, how long it
  # takes and how often it fails are measured rather than assumed.
  class ListReader < ApplicationService
    Result = Struct.new(:lines, :path, :reason, :model_ms, :unresolved, keyword_init: true)

    # Seconds the person may wait after releasing the mic, for every provider
    # in the chain together. A heuristic, not a verified figure: on 2026-11-18
    # gpt-6-luna answered within 3.2 s on all 152 eval calls, measured from a
    # laptop, not from Fly. It fails when the model is slower than that; each
    # dictation logs model_ms, so it is tuned from production numbers.
    TIMEOUT = ENV.fetch("AI_MEMO_PARSE_TIMEOUT_SECONDS", "4").to_f
    MAX_OUTPUT_TOKENS = 600

    def initialize(text:, household:, lang: I18n.locale)
      @text = text.to_s
      @household = household
      @lang = lang
    end

    def call
      split = Text::Segmenter.call(text: @text, household: @household)
      return result(split.parts, "segmenter", "sure", split) if split.sure
      return result(split.parts, "segmenter", "ai_off", split) unless Ai::Config.live?

      started = monotonic_ms
      lines, reason = read_with_model
      elapsed = monotonic_ms - started
      return result(split.parts, "fallback", reason, split, elapsed) if lines.nil?

      result(lines, "model", "unsure", split, elapsed)
    end

    private

    # Returns [lines, nil] or [nil, why the segmenter's lines must be used].
    def read_with_model
      answer = Ai::Router.new(household: @household).json_completion(
        purpose: :memo_parse, schema: ListPrompt::SCHEMA, max_output_tokens: MAX_OUTPUT_TOKENS,
        timeout: TIMEOUT,
        messages: [ { role: "system", content: ListPrompt::SYSTEM }, { role: "user", content: @text } ]
      )
      items = Array(answer["items"]).select { |item| item.is_a?(Hash) && item["name"].to_s.strip.present? }
      return [ nil, "ungrounded" ] unless items.all? { |item| grounded?(item["name"]) }

      [ items.first(Text::Segmenter::MAX_PARTS).map { |item| line(item) }, nil ]
    rescue Ai::Router::BudgetExceeded
      [ nil, "budget" ]
    rescue Ai::Client::TimedOut
      [ nil, "timeout" ]
    rescue Ai::Client::Unavailable
      [ nil, "unavailable" ]
    rescue Ai::Client::Error
      [ nil, "invalid" ]
    end

    # The model chooses among the words that were said; it never adds one. An
    # answer that names an unsaid word is not used at all, because one invented
    # item means the reading as a whole cannot be trusted.
    def grounded?(name)
      (key_words(name) - said_words).empty?
    end

    def said_words = @said_words ||= key_words(@text)

    def key_words(text) = ProductAlias.normalize_key(text).split

    # "2 Kilo Kartoffeln": the same shape the segmenter writes, so a line reads
    # the same whichever path produced it.
    def line(item)
      quantity = item["quantity"]
      amount = quantity.is_a?(Numeric) && quantity.positive? ? format_number(quantity) : nil
      [ amount, item["unit"].to_s.strip.presence, item["name"].to_s.strip ].compact.join(" ").truncate(120)
    end

    def format_number(value)
      ActiveSupport::NumberHelper.number_to_rounded(value, precision: 3, strip_insignificant_zeros: true,
                                                           locale: @lang)
    end

    def result(lines, path, reason, split, model_ms = nil)
      Result.new(lines: lines, path: path, reason: reason, model_ms: model_ms, unresolved: split.unresolved)
    end

    def monotonic_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
  end
end
