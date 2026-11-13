module Recipes
  # Holds a model-written recipe to the food that is actually in the kitchen.
  #
  # The prompt asks the model to use only listed items, and models mostly do —
  # but "mostly" is how an app ends up telling someone to cook with parmesan they
  # never bought. So every ingredient is re-bound to a real item here, each item
  # at most once; anything that cannot be bound is dropped, except optional
  # salt, pepper, oil and water. A recipe left with nothing real to cook is
  # rejected outright (returns nil).
  class GroundInInventory < ApplicationService
    STAPLES = %w[salt salz pepper pfeffer oil öl oel water wasser].freeze
    MIN_TOKEN = 3
    # Receipts and compounds truncate; a shared stem this long counts as a match
    # ("spinat" in "babyspinat"), shorter ones do not ("ei" in "weizenbrötchen").
    MIN_STEM = 4
    MAX_STEPS = 8

    def initialize(recipe:, items:, use_first_ids: [])
      @recipe = recipe.is_a?(Hash) ? recipe : {}
      @items = items
      @use_first_ids = use_first_ids.to_set
      @used_ids = Set.new
    end

    def call
      title = @recipe["title"].to_s.strip
      return nil if title.blank?

      ingredients = Array(@recipe["ingredients"]).filter_map { |raw| bind(raw) if raw.is_a?(Hash) }
      required = ingredients.reject { |i| i[:optional] }
      return nil if required.empty?

      {
        title: title.truncate(120),
        minutes: minutes,
        ingredients: ingredients,
        steps: steps_covering(required),
        use_first_count: required.count { |i| i[:use_first] }
      }
    end

    private

    def bind(raw)
      name = raw["name"].to_s.strip
      optional = raw["optional"] == true
      item = by_id(raw["item_id"]) || by_exact_name(name) || by_alias(name) || by_name(name)

      if item
        @used_ids << item.id
        return { item_id: item.id, name: bare_name(item), amount: amount(raw), optional: optional,
                 use_first: @use_first_ids.include?(item.id) }
      end

      return nil unless optional && staple?(name)

      { item_id: nil, name: name, amount: amount(raw), optional: true, use_first: false }
    end

    def available = @items.reject { |item| @used_ids.include?(item.id) }

    def by_id(id)
      available.find { |item| item.id == id.to_i } if id.present?
    end

    def by_exact_name(name)
      wanted = name.downcase
      available.find { |item| bare_name(item).downcase == wanted || item.canonical_name == wanted }
    end

    # The receipt dictionary already knows that "Rispentomaten" are tomatoes;
    # reuse it before falling back to raw token overlap.
    def by_alias(name)
      entry = ProductAlias.lookup(name)
      return nil if entry.nil?

      canonical = entry.canonical_name.downcase
      available.find { |item| tokens(item.canonical_name).include?(canonical) || item.canonical_name == canonical }
    end

    def by_name(name)
      wanted = tokens(name)
      return nil if wanted.empty?

      scored = available.map { |item| [ item, overlap(wanted, tokens("#{bare_name(item)} #{item.canonical_name}")) ] }
      best, score = scored.max_by { |_, s| s }
      score.to_i.positive? ? best : nil
    end

    # An exact word is worth two, a shared stem one — the same weighting restlos
    # used, with a minimum stem so short words cannot match inside long ones.
    def overlap(wanted, candidate)
      wanted.sum do |word|
        if candidate.include?(word) then 2
        elsif candidate.any? { |c| stem_match?(word, c) } then 1
        else 0
        end
      end
    end

    def stem_match?(left, right)
      shorter, longer = [ left, right ].sort_by(&:length)
      shorter.length >= MIN_STEM && longer.include?(shorter)
    end

    def tokens(text)
      text.to_s.downcase.scan(/[[:alnum:]äöüß]+/).select { |t| t.length >= MIN_TOKEN }.uniq
    end

    def staple?(name)
      words = name.downcase.scan(/[[:alnum:]äöüß]+/)
      words.any? { |w| STAPLES.include?(w) || w.end_with?("öl") }
    end

    # Every real ingredient has to appear in the method, or the user is handed a
    # list of food the recipe never actually uses. Missing ones get a plain step.
    def steps_covering(required)
      steps = Array(@recipe["steps"]).map { |s| s.to_s.strip }.reject(&:blank?).first(MAX_STEPS)
      text = steps.join(" ").downcase

      missing = required.reject { |ingredient| mentioned?(ingredient[:name], text) }
      steps + missing.map { |ingredient| I18n.t("recipes.add_step", name: ingredient[:name]) }
    end

    def mentioned?(name, text)
      return true if text.include?(name.downcase)

      words = tokens(name)
      return false if words.empty?

      words.count { |w| text.include?(w) } >= [ 1, words.size / 2 ].max
    end

    def minutes
      value = Integer(@recipe["minutes"], exception: false)
      value&.clamp(1, 240)
    end

    def amount(raw) = raw["amount"].to_s.strip.presence&.truncate(40)

    def bare_name(item) = Copy.bare_name(item).strip
  end
end
