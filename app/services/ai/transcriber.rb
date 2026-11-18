module Ai
  # Server-side speech to text.
  #
  # The client tries the browser's own SpeechRecognition first, which is free
  # and instant; this is the fallback where it is missing (doc 15 §15.2.4).
  #
  # Both providers document a language hint as improving accuracy and latency,
  # and a prompt as a way to keep punctuation (doc 15 §15.4). The languages are
  # the app's locales, and each one's list-shaped prompt is in
  # config/dictation/<locale>.yml.
  class Transcriber < ApplicationService
    def initialize(io:, filename:, content_type:, duration_seconds: 0.0, language: nil, household: nil)
      @io = io
      @language = Dictation::Vocabulary.supported?(language) ? language.to_s : nil
      @filename = filename
      @content_type = content_type.presence || "audio/webm"
      @duration_seconds = duration_seconds.to_f
      @household = household
    end

    def call
      return Stub.transcript unless Config.live?

      Router.new(household: @household).transcribe(
        io: @io, filename: @filename, content_type: @content_type,
        duration_seconds: @duration_seconds, language: @language,
        prompt: @language && Dictation::Vocabulary.for(@language).transcription_prompt
      )
    end
  end
end
