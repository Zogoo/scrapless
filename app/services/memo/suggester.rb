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

    STAPLES = [
      %w[milk dairy], %w[bread bakery], %w[eggs dairy], %w[butter dairy],
      %w[cheese dairy], %w[onions produce], %w[potatoes produce], %w[tomatoes produce],
      %w[bananas produce], %w[apples produce], %w[chicken meat_fish], %w[coffee drinks],
      %w[rice pantry], %w[pasta pantry], %w[yoghurt dairy], %w[salad produce]
    ].freeze

    Suggestion = Struct.new(:name, :category, :reason, :score, keyword_init: true)

    def initialize(household:, query: nil, limit: LIMIT)
      @household = household
      @query = query.to_s.strip.downcase
      @limit = limit
    end

    # Overdue on this household's own rhythm already means "probably gone", so
    # those are not held back by the at-home rule; history and staples are.
    def call
      candidates = (due_to_run_out.reject { |s| hidden?(s) } +
                    (previously_bought + staples).reject { |s| hidden?(s) || at_home.include?(s.name.downcase) })
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
      Suggestion.new(name: suggestion.name, category: suggestion.category,
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
        Suggestion.new(name: display_name(name), category: category_for(name),
                       reason: I18n.t("memo.reason.due", cadence: cadence, elapsed: elapsed),
                       score: 100 + [ overdue, 30 ].min)
      end
    end

    def previously_bought
      counts = @household.items.group(:canonical_name).count
      counts.map do |name, count|
        Suggestion.new(name: display_name(name), category: category_for(name),
                       reason: I18n.t("memo.reason.bought", count: count), score: 40 + [ count, 20 ].min)
      end
    end

    def staples
      STAPLES.map.with_index do |(key, category), index|
        Suggestion.new(name: I18n.t("memo.staples.#{key}"), category: category,
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
    def at_home
      @at_home ||= @household.items.active.where(window_end: Date.current..)
                             .distinct.pluck(:canonical_name).to_set(&:downcase)
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
      @categories ||= @household.items.pluck(:canonical_name, :category).to_h
      @categories[name].presence || Categories.guess(name)
    end

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
    end
  end
end
