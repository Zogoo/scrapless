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

      items = food.filter_map { |line| build_item(line) }
      Item.transaction { items.each(&:save!) }
      items.each { |item| log_capture_event(item) }

      @capture.update!(
        status: items.any? ? "parsed" : "failed",
        merchant: @payload["merchant"].presence,
        purchased_on: purchased_on,
        line_count: lines.size,
        parse_confidence: confidence(lines, items),
        error_message: items.any? ? nil : "no food lines found"
      )

      { items: items, suppressed: suppressed.map { |l| l["raw_text"].presence || l["name"] }.compact,
        notes: @payload["notes"].presence, kind: @payload["kind"].presence || "receipt" }
    end

    private

    # A deposit line is not food, and proving we filtered it is what makes the
    # parser trustworthy — so suppressed lines are returned, not dropped.
    def food?(line)
      return false if line["food"] == false

      name = "#{line['name']} #{line['raw_text']}".downcase
      return false if name.match?(/pfand|leergut|tragetasche|tasche|rabatt|coupon|payback|summe|total/)

      line["name"].present? || line["raw_text"].present?
    end

    def build_item(line)
      resolved = Items::Resolver.call(
        raw_text: line["raw_text"], name: line["name"],
        category: line["category"], merchant: @payload["merchant"],
        storage: line["storage"]
      )

      window = Freshness::Estimator.call(
        category: resolved.category, storage: resolved.storage, acquired_on: purchased_on
      )

      @household.items.new(
        capture: @capture,
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
        date_label_type: window.high_risk ? "verbrauchsdatum" : "none"
      )
    rescue StandardError => e
      Rails.logger.warn("skipped line #{line.inspect}: #{e.message}")
      nil
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

    def numeric(value)
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
