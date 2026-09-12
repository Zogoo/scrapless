module Memo
  # Autosuggest for the shopping memo.
  #
  # Three sources, in descending order of how much they know about this
  # household: what it buys and is now out of, what it has ever bought, and a
  # global staples list for a fridge with no history yet.
  class Suggester < ApplicationService
    LIMIT = 12

    STAPLES = [
      %w[Milk dairy], %w[Bread bakery], %w[Eggs dairy], %w[Butter dairy],
      %w[Cheese dairy], %w[Onions produce], %w[Potatoes produce], %w[Tomatoes produce],
      %w[Bananas produce], %w[Apples produce], %w[Chicken meat_fish], %w[Coffee drinks],
      %w[Rice pantry], %w[Pasta pantry], %w[Yoghurt dairy], %w[Salad produce]
    ].freeze

    Suggestion = Struct.new(:name, :category, :reason, :score, keyword_init: true)

    def initialize(household:, query: nil, limit: LIMIT)
      @household = household
      @query = query.to_s.strip.downcase
      @limit = limit
    end

    def call
      candidates = (due_to_run_out + previously_bought + staples)
                   .reject { |s| already_on_memo?(s.name) }
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
        Suggestion.new(name: name.titleize, category: category_for(name),
                       reason: "usually every #{cadence} days, last bought #{elapsed} days ago",
                       score: 100 + [ overdue, 30 ].min)
      end
    end

    def previously_bought
      counts = @household.items.group(:canonical_name).count
      counts.map do |name, count|
        Suggestion.new(name: name.to_s.titleize, category: category_for(name),
                       reason: "bought #{count} #{'time'.pluralize(count)} before", score: 40 + [ count, 20 ].min)
      end
    end

    def staples
      STAPLES.map.with_index do |(name, category), index|
        Suggestion.new(name: name, category: category, reason: "common", score: 20 - index * 0.1)
      end
    end

    def purchase_history
      @purchase_history ||= @household.items
                                      .order(:acquired_on)
                                      .pluck(:canonical_name, :acquired_on)
                                      .group_by(&:first)
                                      .transform_values { |rows| rows.map(&:last).uniq.sort }
    end

    def category_for(name)
      @categories ||= @household.items.pluck(:canonical_name, :category).to_h
      @categories[name].presence || Categories.guess(name)
    end

    def already_on_memo?(name)
      @open_names ||= @household.memo_items.open.pluck(:canonical_name).compact.map(&:downcase)
      @open_names.include?(name.downcase)
    end

    def median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round
    end
  end
end
