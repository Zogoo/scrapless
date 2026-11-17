module Items
  # The slider opened this pack, and the thumb is back where that drag began.
  #
  # The open is already saved by then, and a level change usually sits on top
  # of it, so Items::Undo — last event only, and only for a few minutes —
  # cannot reach it. This looks for the open the slider itself wrote and puts
  # the window back. A pack that was already open before that drag is left
  # alone: the slider may change how much is left, never the dates.
  class RevertSliderOpen < ApplicationService
    def initialize(item:, percent:)
      @item = item
      @percent = percent
    end

    def call
      event = matching_open
      return @item unless event

      before = event.meta_payload.fetch("before", {})
      Item.transaction do
        @item.update!(window_start: before["window_start"], window_end: before["window_end"],
                      opened_on: nil)
        event.destroy!
      end
      @item
    end

    private

    # The latest slider open that started at this percent, and that is what
    # opened the pack. A move since then keeps the window the move computed.
    def matching_open
      percent = slider_percent
      return nil if percent.nil? || @item.state != "active" || @item.opened_on.blank?

      @item.item_events.where(kind: "opened").order(at: :desc, id: :desc).detect do |event|
        payload = event.meta_payload
        was = payload["before"] || {}
        payload["source"] == "slider" && payload["start_percent"].to_i == percent &&
          was["opened_on"].blank? && was["storage"] == @item.storage
      end
    end

    # "100abc".to_i is 100. Only a plain percent is a place the thumb was.
    def slider_percent
      return nil unless @percent.to_s.match?(/\A\d{1,3}\z/)

      percent = @percent.to_i
      percent if (0..100).cover?(percent)
    end
  end
end
