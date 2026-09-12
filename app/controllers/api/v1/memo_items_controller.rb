module Api
  module V1
    # The shopping memo. Its own object, not a view of inventory: what you intend
    # to buy and what is rotting have different lifecycles.
    class MemoItemsController < ApplicationController
      def index
        render json: {
          items: current_household.memo_items.ordered.map { |m| memo_json(m) },
          suggestions: suggestion_list
        }
      end

      def create
        item = current_household.memo_items.create!(
          name: params[:name], note: params[:note].presence, source: source_param
        )
        render json: memo_json(item), status: :created
      end

      # Voice or text, several lines at once. This is the "just say it on the way
      # out of the door" path, so it must accept a whole sentence.
      def dictate
        transcript = params[:transcript].presence || transcribe
        return if performed?
        return render json: { error: "nothing heard" }, status: :unprocessable_content if transcript.blank?

        names = extract_names(transcript)
        created = names.map do |name|
          current_household.memo_items.create!(name: name, source: params[:transcript].present? ? "voice" : "voice")
        end

        render json: { transcript: transcript, items: created.map { |m| memo_json(m) } }, status: :created
      end

      def update
        item = current_household.memo_items.find(params[:id])
        item.update!(memo_params)
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

      def transcribe
        upload = params[:audio]
        return render json: { error: "no audio" }, status: :unprocessable_content if upload.blank?

        data = upload.read
        Ai::Transcriber.call(io: StringIO.new(data), filename: upload.original_filename,
                             content_type: upload.content_type,
                             duration_seconds: params[:duration_seconds].to_f,
                             household: current_household)
      end

      # A memo line does not need to be a resolved product — "something for
      # Sunday" is a legitimate entry. So this splits locally and never calls a
      # model: the memo is the one place where cost per line should be zero.
      def extract_names(transcript)
        transcript.split(Text::Splitter::SEPARATORS)
                  .map { |part| part.strip.squeeze(" ") }
                  .reject(&:blank?)
                  .first(25)
                  .map { |part| part.sub(/\A(buy|get|kauf|hol)\s+/i, "").capitalize }
      end

      def memo_json(item)
        {
          id: item.id, name: item.name, note: item.note, done: item.done,
          source: item.source, position: item.position, created_at: item.created_at
        }
      end
    end
  end
end
