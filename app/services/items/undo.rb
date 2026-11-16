module Items
  # Takes back the last tap on a food, if it was a tap and it was just now.
  #
  # Only the most recent event can be undone, only one written by
  # Items::Resolve (it carries the item as it was), and only for a few minutes:
  # this is for a mis-tap, not for rewriting history. The event is deleted
  # rather than countered, because ItemEvent is an audit log and not a ledger
  # (doc 5 §5.3), and because the presence model counts partial_use events.
  class Undo < ApplicationService
    class NotUndoable < StandardError; end

    WINDOW = 10.minutes

    def initialize(item:)
      @item = item
    end

    def call
      event = @item.item_events.order(:at, :id).last
      before = event&.meta_payload&.fetch("before", nil)
      raise NotUndoable if before.nil? || event.at < WINDOW.ago

      Item.transaction do
        @item.update!(before.slice(*Resolve::TRACKED))
        event.destroy!
      end
      @item
    end
  end
end
