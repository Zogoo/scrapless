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
  #      today when the food moved somewhere else (doc 5 §5.3 storage_changed_at),
  #      but from the day it was bought when the place is fixed while
  #      unpacking (the review screen): it was never kept in the wrong place;
  #   3. the dictionary learns the corrected pair, in this kitchen only.
  class Correct < ApplicationService
    WINDOW_INPUTS = %w[category storage date_label_type date_label_value].freeze

    def initialize(item:, changes:)
      @item = item
      @changes = changes.to_h.stringify_keys
    end

    def call
      @item.assign_attributes(@changes)
      if @item.display_name_changed?
        recategorise unless @changes.key?("category")
        keep_emoji
        reidentify
      end
      rewindow if @item.changed.intersect?(WINDOW_INPUTS)

      Item.transaction do
        @item.save!
        teach_dictionary
        ProductAlias.remember_place!(household: @item.household, item: @item) if @item.saved_change_to_storage?
        log_event
      end
      @item
    end

    private

    # A new name may be a different food, so the old product cannot stand. An
    # exact dictionary entry for the new name says which product it is; with
    # none, the item has no product until the model next reads that food.
    def reidentify
      @item.product = ProductAlias.lookup(Copy.bare_name(@item), household: @item.household, fuzzy: false)&.product
    end

    def recategorise
      guess = Resolver.call(raw_text: "", name: @item.display_name, household: @item.household).category
      @item.category = guess unless guess == "other"
    end

    # People type a name, not an emoji; the list shows one on every line. The
    # food keeps its own (🧀 stays 🧀) unless its category changed, in which
    # case the new category's stands in.
    def keep_emoji
      return if Copy.bare_name(@item) != @item.display_name

      @item.display_name = "#{emoji} #{@item.display_name}"
    end

    def emoji
      own = @item.display_name_was.to_s[Copy::LEADING_EMOJI]&.strip
      return own if own.present? && !@item.category_changed?

      Resolver::EMOJI.fetch(@item.category, Resolver::EMOJI["other"])
    end

    def rewindow
      moved = @item.storage_changed? && !placed_on_arrival?
      @item.storage_changed_at = Time.current if moved

      window = Freshness::Estimator.call(
        category: @item.category, storage: @item.storage,
        acquired_on: moved ? Date.current : @item.acquired_on,
        date_label_type: @item.date_label_type, date_label_value: @item.date_label_value,
        opened_on: @item.opened_on, product: @item.product
      )
      @item.assign_attributes(window_start: window.window_start, window_end: window.window_end,
                              confidence: window.confidence)
    end

    # Unpacking: added today, bought today or yesterday (a receipt snapped the
    # morning after), and its place fixed now. That corrects where it went; it
    # is not a move after days somewhere else. Food entered late, bought days
    # ago, has been kept somewhere all that time, so it moves from today.
    def placed_on_arrival?
      @item.created_at.present? && @item.created_at.to_date == Date.current &&
        @item.acquired_on.present? && @item.acquired_on >= Date.current - 1
    end

    def teach_dictionary
      return unless @item.raw_text.present? && @item.saved_change_to_display_name?

      ProductAlias.record_correction!(
        household: @item.household, raw_text: @item.raw_text, canonical_name: @item.canonical_name,
        category: @item.category, merchant: @item.capture&.merchant, product: @item.product
      )
    end

    def log_event
      changed = @item.saved_changes.keys - %w[updated_at lock_version]
      @item.item_events.create!(household: @item.household, kind: "corrected", at: Time.current,
                                meta: { changed: changed }.to_json)
    end
  end
end
