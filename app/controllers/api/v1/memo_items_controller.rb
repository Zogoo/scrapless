module Api
  module V1
    # The shopping memo. Its own object, not a view of inventory: what you intend
    # to buy and what is rotting have different lifecycles.
    class MemoItemsController < ApplicationController
      include InputLimits

      GESTURES = %w[hold tap key].freeze

      def index
        render json: {
          items: current_household.memo_items.ordered.map { |m| memo_json(m) },
          suggestions: suggestion_list
        }
      end

      # Two people adding "milk" to one shared list get one line, not two.
      def create
        existing = current_household.memo_items.open_line_for(params[:name])
        return render json: memo_json(existing) if existing

        item = current_household.memo_items.create!(
          name: params[:name], note: params[:note].presence, source: source_param,
          added_by_name: actor_name
        )
        render json: memo_json(item), status: :created
      end

      # Voice or text, several lines at once. This is the "just say it on the way
      # out of the door" path, so it must accept a whole sentence — or, held one
      # item at a time, a single word.
      def dictate
        transcript = params[:transcript].presence || transcribe
        return if performed?
        return render_error(I18n.t("memo.nothing_heard")) if transcript.blank?
        return render_error(I18n.t("capture.rejected.too_long")) if transcript.length > MAX_TEXT_CHARS

        created = extract_names(transcript).filter_map do |name|
          next if current_household.memo_items.open_line_for(name)

          current_household.memo_items.create!(name: name, source: "voice", added_by_name: actor_name)
        end
        log_dictation(created.size)

        render json: { transcript: transcript, items: created.map { |m| memo_json(m) } }, status: :created
      end

      def update
        item = current_household.memo_items.find(params[:id])
        previous_name = item.name
        item.update!(memo_params)
        Memo::LearnFromCorrection.call(item: item, previous_name: previous_name) if item.saved_change_to_name?
        item.update!(done_at: item.done? ? Time.current : nil) if item.saved_change_to_done?
        render json: memo_json(item)
      end

      def destroy
        current_household.memo_items.find(params[:id]).destroy!
        head :no_content
      end

      def suggestions
        render json: suggestion_list
      end

      # "Stop suggesting this." For a junk line, or something bought once.
      def dismiss_suggestion
        current_household.suggestion_dismissals.find_or_create_by!(canonical_name: params.require(:name))
        render json: suggestion_list
      end

      # Bought lines pile up otherwise; this clears them in one tap.
      def clear_done
        current_household.memo_items.where(done: true).delete_all
        head :no_content
      end

      private

      def suggestion_list
        Memo::Suggester.call(household: current_household, query: params[:q]).map do |s|
          { name: s.name, category: s.category, reason: s.reason }
        end
      end

      def memo_params
        params.require(:memo_item).permit(:name, :note, :done, :position)
      end

      def source_param
        value = params[:source].to_s
        MemoItem::SOURCES.include?(value) ? value : "text"
      end

      # Only Firefox on Android and iPhones with Siri off get here: everywhere
      # else the browser transcribes for free (doc 15 §15.2.4). This path is
      # paid, so it is capped like capture's.
      def transcribe
        upload = params[:audio]
        return render_error(I18n.t("capture.rejected.no_audio")) if upload.blank?
        return render_error(I18n.t("capture.rejected.audio_too_large")) if upload.size > MAX_AUDIO_BYTES
        if transcriptions_this_hour >= MAX_TRANSCRIPTIONS_PER_HOUR
          return render json: { error: I18n.t("memo.too_many_recordings"), retryable: true }, status: :too_many_requests
        end

        Ai::Transcriber.call(io: StringIO.new(upload.read), filename: upload.original_filename,
                             content_type: upload.content_type,
                             duration_seconds: params[:duration_seconds].to_f,
                             language: speech_language, household: current_household)
      end

      def transcriptions_this_hour
        AiCall.where(household: current_household, purpose: "transcribe", created_at: 1.hour.ago..).count
      end

      # The language the person spoke, which is not always the app's language:
      # an English UI in a German supermarket is the common Berlin case.
      def speech_language
        Dictation::Vocabulary.supported?(params[:lang]) ? params[:lang].to_s : I18n.locale.to_s
      end

      # How the mic was used, so the hold threshold and the default gesture are
      # decided from numbers (doc 15 §15.8.5) rather than guessed.
      def log_dictation(lines)
        Rails.logger.info(
          "memo dictation household=#{current_household.id} gesture=#{gesture_param} " \
          "press_ms=#{params[:press_ms].to_i} lang=#{speech_language} ui=#{I18n.locale} lines=#{lines}"
        )
      end

      # A memo line does not need to be a resolved product — "something for
      # Sunday" is a legitimate entry. So this splits locally and never calls a
      # model: the memo is the one place where cost per line should be zero.
      # Sentences the dictionary could not split at all are logged, so how often
      # a model would have helped is measured before one is ever added.
      def extract_names(transcript)
        result = Text::Segmenter.call(text: transcript, household: current_household)
        if result.unresolved.any?
          Rails.logger.info("memo dictation unresolved household=#{current_household.id} " \
                            "chunks=#{result.unresolved.size}")
        end
        result.parts
      end

      # Only known values reach the log: a free-form param could forge lines.
      def gesture_param = GESTURES.include?(params[:gesture].to_s) ? params[:gesture].to_s : "unknown"

      def render_error(message)
        render json: { error: message }, status: :unprocessable_content
      end

      def memo_json(item)
        {
          id: item.id, name: item.name, note: item.note, done: item.done,
          source: item.source, position: item.position, created_at: item.created_at,
          added_by_name: item.added_by_name
        }
      end
    end
  end
end
