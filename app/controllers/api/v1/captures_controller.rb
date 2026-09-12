module Api
  module V1
    # The one screen that has to work. Everything else is scaffolding.
    class CapturesController < ApplicationController
      MAX_IMAGE_BYTES = 8.megabytes
      MAX_AUDIO_BYTES = 12.megabytes

      # Every capture can cost a model call, and there is no account wall in
      # front of this endpoint — a fridge is free to create. So the blast radius
      # of someone looping an upload has to be bounded by something.
      #
      # Counted out of the captures table rather than a cache counter, because a
      # cache flush must not reset a spending limit. 40/hour is roughly twenty
      # times the heaviest plausible real week, compressed into one hour.
      MAX_CAPTURES_PER_HOUR = 40

      before_action :enforce_capture_budget, only: :create

      def create
        capture = current_household.captures.new(source: source_param)

        payload =
          case capture.source
          when "receipt", "shelf_photo" then from_image(capture)
          when "voice"                  then from_voice(capture)
          when "text", "grid"           then from_text(capture)
          end
        return if performed?

        capture.raw_payload = payload
        capture.save!

        result = Captures::Ingest.call(capture: capture, payload: payload)
        render json: review_json(capture, result), status: :created
      end

      def show
        capture = current_household.captures.find(params[:id])
        render json: {
          id: capture.id, source: capture.source, status: capture.status,
          merchant: capture.merchant, purchased_on: capture.purchased_on,
          parse_confidence: capture.parse_confidence,
          items: capture.items.map { |i| { id: i.id, display_name: i.display_name } }
        }
      end

      private

      def enforce_capture_budget
        recent = current_household.captures.where(created_at: 1.hour.ago..).count
        return if recent < MAX_CAPTURES_PER_HOUR

        render json: { error: I18n.t("capture.too_many"), retryable: true },
               status: :too_many_requests
      end

      def source_param
        value = params[:source].to_s
        Capture::SOURCES.include?(value) ? value : "text"
      end

      def from_image(capture)
        upload = params[:image]
        return reject("no image") if upload.blank?
        return reject("image too large") if upload.size > MAX_IMAGE_BYTES

        data = upload.read
        capture.image.attach(io: StringIO.new(data), filename: upload.original_filename,
                             content_type: upload.content_type)

        Ai::ImageReader.call(image_data: data, content_type: upload.content_type,
                             household: current_household, hint: capture.source)
      end

      # Two ways in. The browser's own recogniser is free, so when the client
      # sends a transcript we never touch the audio endpoint at all; audio only
      # arrives from Safari, which has no SpeechRecognition.
      def from_voice(capture)
        transcript = params[:transcript].presence || transcribe(capture)
        return if performed?

        capture.transcript = transcript
        lines_from(transcript)
      end

      def transcribe(capture)
        upload = params[:audio]
        return reject("no audio") if upload.blank?
        return reject("audio too large") if upload.size > MAX_AUDIO_BYTES

        data = upload.read
        capture.audio.attach(io: StringIO.new(data), filename: upload.original_filename,
                             content_type: upload.content_type)

        Ai::Transcriber.call(io: StringIO.new(data), filename: upload.original_filename,
                             content_type: upload.content_type,
                             duration_seconds: params[:duration_seconds].to_f,
                             household: current_household)
      end

      # Manual entry asks for one thing: what you got. The dictionary resolves
      # what it can for free and only the leftovers reach a model.
      def from_text(capture)
        text = params[:text].to_s.strip
        return reject("no text") if text.blank?

        capture.transcript = text
        lines_from(text)
      end

      # Shared by the typed and spoken paths, because they are the same problem:
      # some words we already know, some we do not.
      #
      # Routing voice through the dictionary too is not just tidiness — "milch
      # und brokkoli" spoken now costs nothing at all, where before every spoken
      # sentence bought a model call whether it needed one or not.
      def lines_from(text)
        known, unknown = Text::Splitter.call(text: text)
        parsed, note = parse_unknown(unknown)

        { "lines" => known + parsed, "notes" => note }
      end

      # Never lose what we already understood.
      #
      # The dictionary hits are correct whatever the model does, and throwing
      # them away because one unfamiliar word could not be parsed is exactly the
      # dead end doc 4 §4.4 rule 4 forbids — observed live against a provider
      # returning 429, where "milch, brokkoli, yuzu kosho" lost all three.
      def parse_unknown(unknown)
        return [ [], nil ] if unknown.empty?

        result = Ai::TextReader.call(text: unknown.join(", "), household: current_household)
        [ Array(result["items"]), nil ]
      rescue Ai::Client::Error => e
        Rails.logger.warn("text parse failed, keeping #{unknown.size} dictionary hits: #{e.message}")
        [ [], I18n.t("capture.partial_parse", list: unknown.join(", ")) ]
      end

      def reject(message)
        render json: { error: message }, status: :unprocessable_content
        nil
      end

      def review_json(capture, result)
        {
          capture: {
            id: capture.id, source: capture.source, kind: result[:kind],
            merchant: capture.merchant, purchased_on: capture.purchased_on,
            status: capture.status, parse_confidence: capture.parse_confidence,
            line_count: capture.line_count, transcript: capture.transcript,
            notes: result[:notes]
          },
          items: result[:items].map do |item|
            {
              id: item.id, display_name: item.display_name, category: item.category,
              raw_text: item.raw_text, quantity: item.quantity&.to_f, unit: item.unit,
              storage: item.storage, window_end: item.window_end,
              days_left: item.days_left, confidence: item.confidence,
              needs_review: item.confidence < 0.5
            }
          end,
          suppressed: result[:suppressed]
        }
      end
    end
  end
end
