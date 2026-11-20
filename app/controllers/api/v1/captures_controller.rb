module Api
  module V1
    # The one screen that has to work. Everything else is scaffolding.
    class CapturesController < ApplicationController
      include InputLimits

      # Every capture can cost a model call. Counted out of the captures table
      # rather than a cache counter, because a cache flush must not reset a
      # spending limit (limits: InputLimits).

      before_action :enforce_capture_budget, only: :create

      def create
        capture = current_household.captures.new(source: source_param, added_by_name: actor_name)

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
        return reject(:no_image) if upload.blank?
        return reject(:too_large) if upload.size > MAX_IMAGE_BYTES

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
        return reject(:too_long) if transcript.to_s.length > MAX_TEXT_CHARS

        capture.transcript = transcript
        lines_from(transcript)
      end

      def transcribe(capture)
        upload = params[:audio]
        return reject(:no_audio) if upload.blank?
        return reject(:too_large) if upload.size > MAX_AUDIO_BYTES

        data = upload.read
        capture.audio.attach(io: StringIO.new(data), filename: upload.original_filename,
                             content_type: upload.content_type)

        Ai::Transcriber.call(io: StringIO.new(data), filename: upload.original_filename,
                             content_type: upload.content_type,
                             duration_seconds: params[:duration_seconds].to_f,
                             language: params[:lang].presence || I18n.locale.to_s,
                             household: current_household)
      end

      # Manual entry asks for one thing: what you got. The dictionary resolves
      # what it can for free and only the leftovers reach a model.
      def from_text(capture)
        text = params[:text].to_s.strip
        return reject(:no_text) if text.blank?
        return reject(:too_long) if text.length > MAX_TEXT_CHARS

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
        known, unknown = Text::Splitter.call(text: text, household: current_household)
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

      def reject(reason)
        render json: { error: I18n.t("capture.rejected.#{reason}") }, status: :unprocessable_content
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
          items: result[:items].each_with_index.map do |item, index|
            {
              id: item.id, display_name: item.display_name, category: item.category,
              raw_text: item.raw_text, quantity: item.quantity&.to_f, unit: item.unit,
              storage: item.storage, window_end: item.window_end,
              days_left: item.days_left, confidence: item.confidence,
              needs_review: item.confidence < 0.5,
              in_kitchen: in_kitchen(item),
              # The merged product, as the Kitchen will show it ("Reis" over
              # "Basmatireis"); merged only when the variety became another product.
              product_name: item.product&.names&.dig(I18n.locale.to_s),
              merged: merged?(item),
              joins: joins(item),
              box: result[:boxes]&.at(index),
              added_by_name: item.added_by_name
            }
          end,
          suppressed: result[:suppressed]
        }
      end

      # Adding milk when there is already milk joins the same Kitchen line rather
      # than silently becoming an unrelated second row; the review says so.
      # Counted the way the Kitchen groups lines (line.ts): the same product,
      # or the same name for packs that have no product.
      def in_kitchen(item) = same_line(item).count

      # Every active pack on the Kitchen line this item lands on (line.ts): the
      # same product, or the same name for packs that have no product.
      def same_line(item)
        packs = current_household.items.active.where(storage: item.storage)
        return packs.where(canonical_name: item.canonical_name) if item.product_id.nil?

        packs.where(product_id: item.product_id).or(packs.where(canonical_name: item.canonical_name, product_id: nil))
      end

      def merged?(item)
        item.product.present? && item.source_product_key.present? && item.source_product_key != item.product.key
      end

      # The line a pack joins when it is called something else there: Tilsiter
      # on a "Käse" line. Named the way the Kitchen titles it, by the pack that
      # goes off first. Not for a merged variety: its title already is the line
      # ("Reis"). nil when it joins nothing or a line of its own name.
      def joins(item)
        return nil if merged?(item)

        other = same_line(item).where.not(id: item.id).order(:window_end, :id).first
        name = other && Copy.bare_name(other)
        name unless name.nil? || name.casecmp?(Copy.bare_name(item))
      end
    end
  end
end
