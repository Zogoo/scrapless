module Ai
  # Server-side speech to text.
  #
  # The client tries the browser's own SpeechRecognition first, which is free and
  # instant; this is the fallback for Safari, which does not have it. So this
  # path carries roughly the iOS share of traffic, not all of it.
  class Transcriber < ApplicationService
    LANGUAGES = %w[de en].freeze

    # Both providers document a language hint as improving accuracy and latency,
    # and a prompt as a way to keep punctuation (doc 15 §15.4). A list-shaped
    # prompt in the spoken language asks for commas between items. It must match
    # the audio's language, so there is one per language.
    PROMPTS = {
      "de" => "Einkaufsliste: Milch, Brot, Eier, Klopapier.",
      "en" => "Shopping list: milk, bread, eggs, toilet paper."
    }.freeze

    def initialize(io:, filename:, content_type:, duration_seconds: 0.0, language: nil, household: nil)
      @io = io
      @language = LANGUAGES.include?(language.to_s) ? language.to_s : nil
      @filename = filename
      @content_type = content_type.presence || "audio/webm"
      @duration_seconds = duration_seconds.to_f
      @household = household
    end

    def call
      return Stub.transcript unless Config.live?

      Router.new(household: @household).transcribe(
        io: @io, filename: @filename, content_type: @content_type,
        duration_seconds: @duration_seconds, language: @language, prompt: PROMPTS[@language]
      )
    end
  end
end
