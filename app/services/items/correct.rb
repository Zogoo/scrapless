module Items
  # A person fixing what the app got wrong about one item.
  #
  # A correction has to reach everything that was derived from the wrong
  # answer, or it fixes the label and leaves the harm. Observed: bread filed as
  # dairy, renamed in the Kitchen, kept dairy's 14-day fridge window — and the
  # dictionary learned the new name *with the old category*.
  #
  # So, in order:
  #   1. a rename re-reads the category from the new name, unless the client
  #      sent one or the new name tells us nothing ("other");
  #   2. anything the window was computed from changed -> recompute it, from
  #      today when the food moved somewhere else (doc 5 §5.3 storage_changed_at);
  #   3. the dictionary learns the corrected pair, in this kitchen only.
  class Correct < ApplicationService
    WINDOW_INPUTS = %w[category storage date_label_type date_label_value].freeze

    def initialize(item:, changes:)
      @item = item
      @changes = changes.to_h.stringify_keys
    end

    def call
      @item.assign_attributes(@changes)
      recategorise if @item.display_name_changed? && !@changes.key?("category")
      rewindow if @item.changed.intersect?(WINDOW_INPUTS)

      Item.transaction do
        @item.save!
        teach_dictionary
        log_event
      end
      @item
    end

    private

    def recategorise
      guess = Resolver.call(raw_text: "", name: @item.display_name, household: @item.household).category
      @item.category = guess unless guess == "other"
    end

    def rewindow
      moved = @item.storage_changed?
      @item.storage_changed_at = Time.current if moved

      window = Freshness::Estimator.call(
        category: @item.category, storage: @item.storage,
        acquired_on: moved ? Date.current : @item.acquired_on,
        date_label_type: @item.date_label_type, date_label_value: @item.date_label_value,
        opened_on: @item.opened_on
      )
      @item.assign_attributes(window_start: window.window_start, window_end: window.window_end,
                              confidence: window.confidence)
    end

    def teach_dictionary
      return unless @item.raw_text.present? && @item.saved_change_to_display_name?

      ProductAlias.record_correction!(
        household: @item.household, raw_text: @item.raw_text, canonical_name: @item.canonical_name,
        category: @item.category, merchant: @item.capture&.merchant
      )
    end

    def log_event
      changed = @item.saved_changes.keys - %w[updated_at lock_version]
      @item.item_events.create!(household: @item.household, kind: "corrected", at: Time.current,
                                meta: { changed: changed }.to_json)
    end
  end
end
