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
    Spoken = Struct.new(:key, :surface)

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

      items = items.first(Text::Segmenter::MAX_PARTS)
      [ items.each_with_index.map { |item, i| line(item, items[0...i] + items[(i + 1)..]) }, nil ]
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

    # A line in the speaker's own words where that is unambiguous: "Tomaten aus
    # der Dose", not the model's split of it into unit and name ("Dose Tomaten").
    # Otherwise amount, unit, name: "2 Kilo Kartoffeln", the shape the segmenter
    # writes. The amount is always digits.
    def line(item, others)
      quantity = item["quantity"]
      amount = quantity.is_a?(Numeric) && quantity.positive? ? format_number(quantity) : nil
      words = spoken_span(item, others, counted: !amount.nil?) ||
              [ item["unit"].to_s.strip.presence, item["name"].to_s.strip ].compact.join(" ")
      [ amount, words ].compact.join(" ").truncate(120)
    end

    # The shortest stretch of what was said that holds every word of this
    # item's name and unit, if the words in between belong to no other item
    # and, when an amount was given, are not a number (which would repeat it).
    # A rule over the item's own words, not over phrases: it applies to any
    # language. Not used when the stretch crosses into another item, and the
    # eval (script/dictation_eval) measures how the lines come out.
    def spoken_span(item, others, counted:)
      need = key_words("#{item['name']} #{item['unit']}").tally
      taken = others.flat_map { |other| key_words("#{other['name']} #{other['unit']}") }.to_set
      window = shortest_window(need)
      return if window.nil?

      extra = window.map(&:key).tally.filter_map { |word, n| word if n > need.fetch(word, 0) }
      return if extra.any? { |word| taken.include?(word) || (counted && number_word?(word)) }

      window.filter_map(&:surface).join(" ")
    end

    def shortest_window(need)
      best = nil
      spoken.each_index do |from|
        next unless need.key?(spoken[from].key)

        seen = Hash.new(0)
        spoken[from..].each_with_index do |token, offset|
          seen[token.key] += 1
          next unless need.all? { |word, n| seen[word] >= n }

          best = spoken[from, offset + 1] if best.nil? || offset + 1 < best.size
          break
        end
      end
      best
    end

    # What was said, one entry per normalised word, keeping the spoken spelling.
    def spoken
      @spoken ||= @text.split(/\s+/).flat_map do |raw|
        surface = raw.gsub(/\A[^\p{L}\p{N}]+|[^\p{L}\p{N}]+\z/, "")
        key_words(raw).each_with_index.map { |key, i| Spoken.new(key, i.zero? ? surface : nil) }
      end
    end

    def number_word?(word)
      word.match?(/\A\d/) || Dictation::Vocabulary.combined[:numbers].key?(word)
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
