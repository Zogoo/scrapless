module Ai
  # Server-side speech to text.
  #
  # The client tries the browser's own SpeechRecognition first, which is free and
  # instant; this is the fallback for Safari, which does not have it. So this
  # path carries roughly the iOS share of traffic, not all of it.
  class Transcriber < ApplicationService
    def initialize(io:, filename:, content_type:, duration_seconds: 0.0, household: nil)
      @io = io
      @filename = filename
      @content_type = content_type.presence || "audio/webm"
      @duration_seconds = duration_seconds.to_f
      @household = household
    end

    def call
      return Stub.transcript unless Config.live?

      Client.new(household: @household).transcribe(
        io: @io, filename: @filename, content_type: @content_type,
        duration_seconds: @duration_seconds
      )
    end
  end
end
