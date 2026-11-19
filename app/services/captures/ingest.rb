module Captures
  # Turns a parsed payload into items, with a freshness window on each.
  #
  # Nothing here blocks on a failure: if six of twenty-three lines are junk, the
  # other seventeen still land and the review screen says so. A capture that
  # refuses to finish is a capture the user stops making.
  class Ingest < ApplicationService
    def initialize(capture:, payload:, acquired_on: nil)
      @capture = capture
      @household = capture.household
      @payload = payload.is_a?(Hash) ? payload : {}
      @acquired_on = acquired_on
    end

    def call
      lines = Array(@payload["lines"] || @payload["items"])
      food, suppressed = lines.partition { |line| food?(line) }
      food, suppressed = [ [], lines ] if bill?

      resolved = food.filter_map { |line| resolve(line) }
      # Before any window is worked out, so the first pack of a food already
      # gets its own shelf life rather than its category's.
      Products::LearnShelfLife.call(products: resolved.filter_map { |_, r| r.product }, household: @household)
      built = resolved.filter_map { |line, r| build_item(line, r) }
      items = built.map(&:first)
      Item.transaction { items.each(&:save!) }
      items.each { |item| log_capture_event(item) }
      built.each { |item, resolved, line| learn(item, resolved, line) }

      @capture.update!(
        status: items.any? ? "parsed" : "failed",
        merchant: @payload["merchant"].presence,
        purchased_on: purchased_on,
        line_count: lines.size,
        parse_confidence: confidence(lines, items),
        error_message: items.any? ? nil : "no food lines found"
      )

      { items: items, boxes: built.map { |_, _, line| box(line["box"]) },
        suppressed: suppressed.map { |l| l["raw_text"].presence || l["name"] }.compact,
        notes: bill? ? I18n.t("capture.bill") : @payload["notes"].presence,
        kind: @payload["kind"].presence || "receipt" }
    end

    private

    # A meal eaten out (Ai::ImageReader::KINDS): nothing on it is in the
    # kitchen, so every line is left out and listed.
    def bill? = @payload["kind"] == "bill"

    # A deposit line is not food, and proving we filtered it is what makes the
    # parser trustworthy — so suppressed lines are returned, not dropped.
    #
    # The model says what every row is (Ai::ImageReader::ROWS), and that is
    # trusted. A word list used to second-guess it and threw away real food:
    # "Maultaschen" contains "tasche" (bag), "Summer rolls" contains "summe"
    # (total). Typed and spoken lines carry no label: the text reader returns
    # only food, and a dictionary hit is food by definition.
    def food?(line)
      return false if line["food"] == false
      return false unless line.fetch("row", "food") == "food"

      line["name"].present? || line["raw_text"].present?
    end

    def resolve(line)
      resolved = Items::Resolver.call(
        raw_text: line["raw_text"], name: line["name"],
        category: line["category"], merchant: @payload["merchant"],
        storage: line["storage"], household: @household, product: line["product"]
      )
      [ line, resolved ]
    rescue StandardError => e
      Rails.logger.warn("skipped line #{line.inspect}: #{e.message}")
      nil
    end

    def build_item(line, resolved)
      window = Freshness::Estimator.call(
        category: resolved.category, storage: resolved.storage, acquired_on: purchased_on,
        product: resolved.product
      )

      item = @household.items.new(
        capture: @capture,
        product: resolved.product,
        display_name: "#{resolved.emoji} #{resolved.display_name}".strip,
        canonical_name: resolved.canonical_name,
        category: resolved.category,
        raw_text: line["raw_text"].presence,
        quantity: numeric(line["quantity"]),
        unit: line["unit"].presence,
        quantity_confidence: line["quantity"].present? ? 0.8 : 0.3,
        storage: resolved.storage,
        acquired_on: purchased_on,
        window_start: window.window_start,
        window_end: window.window_end,
        confidence: resolved.source == "dictionary" ? window.confidence : [ window.confidence - 0.1, 0.2 ].max,
        added_by_name: @capture.added_by_name
      )
      [ item, resolved, line ]
    rescue StandardError => e
      Rails.logger.warn("skipped line #{line.inspect}: #{e.message}")
      nil
    end

    # Dictionary first, the model for the rest, and the model's answer kept so
    # the dictionary knows it next time (ProductAlias.learn!). Only an answer
    # a live model actually gave: a line it did not place (no category) was
    # guessed here, and the offline stub guesses from a word list. A guess
    # must not teach anything.
    def learn(item, resolved, line)
      return unless Ai::Config.live?
      return unless resolved.source == "heuristic" && Categories.valid?(line["category"])

      ProductAlias.learn!(household: @household, raw_text: item.raw_text || line["name"],
                          canonical_name: item.canonical_name, category: item.category,
                          storage: item.storage, product: resolved.product, emoji: resolved.emoji)
    end

    def log_capture_event(item)
      item.item_events.create!(
        household: @household, kind: "captured", at: Time.current,
        meta: { source: @capture.source, raw_text: item.raw_text }.to_json
      )
    end

    def purchased_on
      @purchased_on ||= @acquired_on || parse_date(@payload["purchased_on"]) || Date.current
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # There is no vendor confidence score to report any more, so this is derived:
    # the share of lines that became something, which is what the user cares about.
    def confidence(lines, items)
      return 0.0 if lines.empty?

      (items.size / lines.size.to_f).round(2)
    end

    # Where a food photo showed each item, for the labels drawn on it in the
    # review. Not stored: it describes one photo, not the food. Anything that is
    # not a sane box inside the image is dropped rather than drawn wrong.
    def box(value)
      return nil unless value.is_a?(Hash)

      x, y, w, h = %w[x y w h].map { |k| numeric(value[k]) }
      return nil unless [ x, y, w, h ].all? { |n| n&.between?(0.0, 1.0) } && w.positive? && h.positive?

      { x: x, y: y, w: [ w, 1.0 - x ].min, h: [ h, 1.0 - y ].min }
    end

    def numeric(value)
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
