module Memo
  # Autosuggest for the shopping memo.
  #
  # Three sources, in descending order of how much they know about this
  # household: what it buys and is now out of, what it has ever bought, and a
  # global staples list for a fridge with no history yet.
  #
  # Never suggested: anything already on the list, anything the kitchen still
  # has and has not outlived (a list that says "buy milk" beside a full carton
  # is noise), and anything this kitchen dismissed.
  class Suggester < ApplicationService
    LIMIT = 12

    # [label key, category, the word a receipt (and the tap grid) uses]. The
    # label follows the UI's language; the word is how the kitchen holds it, so
    # "Milk" is not suggested beside a carton of Milch.
    STAPLES = [
      %w[milk dairy Milch], %w[bread bakery Brot], %w[eggs dairy Eier], %w[butter dairy Butter],
      %w[cheese dairy Käse], %w[onions produce Zwiebeln], %w[potatoes produce Kartoffeln],
      %w[tomatoes produce Tomaten], %w[bananas produce Bananen], %w[apples produce Äpfel],
      %w[chicken meat_fish Hähnchen], %w[coffee drinks Kaffee], %w[rice pantry Reis],
      %w[pasta pantry Nudeln], %w[yoghurt dairy Joghurt], %w[salad produce Salat]
    ].freeze

    # `key` is what "already at home" is checked against; it is the name
    # itself except for staples. `product_id` catches the same food under
    # another name: "Bananas" beside "Banane Chiquita", "Chicken" beside
    # "chicken breast" were both suggested while at home.
    Suggestion = Struct.new(:name, :category, :reason, :score, :key, :product_id, keyword_init: true) do
      def at_home_key = (key || name).downcase
    end

    def initialize(household:, query: nil, limit: LIMIT)
      @household = household
      @query = query.to_s.strip.downcase
      @limit = limit
    end

    # Overdue on this household's own rhythm already means "probably gone", so
    # those are not held back by the at-home rule; history and staples are.
    def call
      candidates = (due_to_run_out.reject { |s| hidden?(s) } +
                    (previously_bought + staples).reject { |s| hidden?(s) || home?(s) })
                   .uniq { |s| s.product_id || s.name.downcase }
                   # A food bought before it had a product, and the staple
                   # with one, were both suggested as "Butter".
                   .uniq { |s| s.name.downcase }

      candidates = matching(candidates) if @query.present?
      candidates.sort_by { |s| -s.score }.first(@limit)
    end

    private

    # Substring matching alone ranks "Broccoli" above "Coffee" for the query
    # "co", because history outscores a staple. In a type-ahead that is simply
    # wrong: what someone has started typing is a stronger signal than what they
    # bought last month, so a prefix hit is promoted above every substring hit.
    def matching(candidates)
      candidates
        .select { |s| s.name.downcase.include?(@query) }
        .map { |s| s.name.downcase.start_with?(@query) ? boost(s) : s }
    end

    def boost(suggestion)
      Suggestion.new(name: suggestion.name, category: suggestion.category, key: suggestion.key,
                     product_id: suggestion.product_id,
                     reason: suggestion.reason, score: suggestion.score + 1000)
    end

    # The genuinely useful half: things this household buys on a rhythm and is
    # now past due on. Comes free from capture history — no extra input, no
    # model call, and it is the reason to open the memo at all.
    def due_to_run_out
      purchase_history.filter_map do |name, dates|
        next if dates.size < 3

        gaps = dates.each_cons(2).map { |a, b| (b - a).to_i }.reject(&:zero?)
        next if gaps.size < 2

        cadence = median(gaps)
        elapsed = (Date.current - dates.last).to_i
        next if elapsed < cadence

        overdue = elapsed - cadence
        Suggestion.new(name: display_name(name), category: category_for(name), product_id: product_for(name),
                       reason: I18n.t("memo.reason.due", cadence: cadence, elapsed: elapsed),
                       score: 100 + [ overdue, 30 ].min)
      end
    end

    def previously_bought
      counts = @household.items.group(:canonical_name).count
      counts.map do |name, count|
        Suggestion.new(name: display_name(name), category: category_for(name), product_id: product_for(name),
                       reason: I18n.t("memo.reason.bought", count: count), score: 40 + [ count, 20 ].min)
      end
    end

    def staples
      STAPLES.map.with_index do |(label, category, word), index|
        Suggestion.new(name: I18n.t("memo.staples.#{label}"), category: category, key: word,
                       product_id: staple_products[ProductAlias.normalize_key(word)],
                       reason: I18n.t("memo.reason.common"), score: 20 - index * 0.1)
      end
    end

    # Already on the list, or dismissed by this kitchen.
    def hidden?(suggestion)
      @hidden ||= (@household.memo_items.open.pluck(:canonical_name).compact +
                   @household.suggestion_dismissals.pluck(:canonical_name)).to_set(&:downcase)
      @hidden.include?(suggestion.name.downcase)
    end

    # Food that is here and has not outlived its window. Past the window we are
    # no longer sure it is here, so suggesting it again is fair.
    def home?(suggestion)
      at_home.include?(suggestion.at_home_key) || at_home_products.include?(suggestion.product_id)
    end

    def at_home = (@at_home ||= fresh_items.distinct.pluck(:canonical_name).to_set(&:downcase))

    def at_home_products = (@at_home_products ||= fresh_items.where.not(product_id: nil).distinct.pluck(:product_id).to_set)

    def fresh_items = @household.items.active.where(window_end: Date.current..)

    # One query for every staple's product, from the shared dictionary.
    def staple_products
      @staple_products ||= ProductAlias.shared.where(raw_text: STAPLES.map { |*, word| ProductAlias.normalize_key(word) })
                                       .pluck(:raw_text, :product_id).to_h
    end

    def product_for(canonical)
      @products ||= @household.items.where.not(product_id: nil).order(:id).pluck(:canonical_name, :product_id).to_h
      @products[canonical]
    end

    def purchase_history
      @purchase_history ||= @household.items
                                      .order(:acquired_on)
                                      .pluck(:canonical_name, :acquired_on)
                                      .group_by(&:first)
                                      .transform_values { |rows| rows.map(&:last).uniq.sort }
    end

    # The name as last shown in this kitchen ("H-Milch"), not a re-capitalised
    # canonical key ("H Milch").
    def display_name(canonical)
      @display_names ||= @household.items.order(:id).pluck(:canonical_name, :display_name)
                                   .to_h { |key, shown| [ key, Copy.bare(shown) ] }
      @display_names[canonical].presence || canonical.to_s.upcase_first
    end

    def category_for(name)
      (@category_for ||= CategoryFor.new(household: @household)).call(name)
    end

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
    end
  end
end
