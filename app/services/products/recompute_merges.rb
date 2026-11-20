module Products
  # Puts every item, and every dictionary entry, on the product the merge list
  # says it belongs to now (`rake products:recompute_merges`).
  #
  # Items keep the key the model first gave them (source_product_key), so this
  # works both ways: adding "rice" to config/product_merge.yml moves basmati and
  # jasmine onto "rice"; taking it out splits them back. Dictionary entries
  # follow the items read from the same text, so the next receipt line lands on
  # the same product; an entry no item explains is merged by its own key.
  #
  # A dry run (the default) only reports. Idempotent: a second run moves nothing.
  class RecomputeMerges < ApplicationService
    Move = Struct.new(:from, :to, :ids, keyword_init: true)

    def initialize(dry_run: true, rules: MergeKey.rules, io: $stdout)
      @dry_run = dry_run
      @rules = rules
      @io = io
    end

    def call
      item_moves = plan_items
      alias_moves = plan_aliases
      unfilled = Item.where(source_product_key: nil).where.not(product_id: nil).count

      report(item_moves, alias_moves, unfilled)
      return { items: item_moves, aliases: alias_moves } if @dry_run

      fill_source_keys
      item_moves.group_by(&:to).each { |target, moves| apply(target, moves, alias_moves) }
      alias_moves.reject { |m| item_moves.any? { |im| im.to == m.to } }
                 .group_by(&:to).each { |target, moves| apply(target, [], moves) }
      delete_orphans(item_moves.map(&:from) + alias_moves.map(&:from))
      { items: item_moves, aliases: alias_moves }
    end

    private

    # [from key, to key] => item ids, for items not on their target yet.
    def plan_items
      moves = Hash.new { |hash, key| hash[key] = [] }
      Item.includes(:product).where.not(product_id: nil).or(Item.where.not(source_product_key: nil))
          .find_each do |item|
        from = item.product&.key
        target = target_for(item)
        moves[[ from, target ]] << item.id if target && from != target
      end
      moves.map { |(from, to), ids| Move.new(from: from, to: to, ids: ids) }
    end

    def plan_aliases
      moves = Hash.new { |hash, key| hash[key] = [] }
      ProductAlias.includes(:product).where.not(product_id: nil).find_each do |entry|
        target = text_targets[entry.raw_text] ||
                 MergeKey.call(key: entry.product.key, category: entry.category, rules: @rules)
        moves[[ entry.product.key, target ]] << entry.id if target != entry.product.key
      end
      moves.map { |(from, to), ids| Move.new(from: from, to: to, ids: ids) }
    end

    def target_for(item)
      source = item.source_product_key.presence || item.product&.key
      source && MergeKey.call(key: source, category: item.category, rules: @rules)
    end

    # Receipt or typed text -> the product its items belong on now, so a
    # dictionary entry splits back with the items it was learned from.
    def text_targets
      @text_targets ||= Item.includes(:product).where.not(raw_text: nil).each_with_object({}) do |item, map|
        target = target_for(item)
        next unless target

        exact = ProductAlias.normalize_key(item.raw_text)
        [ exact, ProductAlias.without_quantities(exact) ].compact_blank.each { |key| map[key] ||= target }
      end
    end

    def fill_source_keys
      Item.where(source_product_key: nil).where.not(product_id: nil).includes(:product).find_each do |item|
        item.update_columns(source_product_key: item.product.key)
      end
    end

    def apply(target_key, item_moves, alias_moves)
      Product.transaction do
        target = Product.create_or_find_by!(key: target_key).name_from_config!
        inherit_shelf_life(target, item_moves)
        item_moves.each { |move| Item.where(id: move.ids).update_all(product_id: target.id) }
        alias_moves.select { |move| move.to == target_key }
                   .each { |move| ProductAlias.where(id: move.ids).update_all(product_id: target.id) }
      end
    end

    # A product new to its items has not been asked about yet: it takes the
    # shelf life of the product most of them come from.
    def inherit_shelf_life(target, moves)
      return if target.shelf_life.present? || moves.empty?

      biggest = moves.max_by { |move| move.ids.size }
      life = Product.find_by(key: biggest.from)&.shelf_life
      target.update!(shelf_life: life) if life.present?
    end

    def delete_orphans(keys)
      Product.where(key: keys.compact.uniq).find_each do |product|
        next if product.items.exists? || product.product_aliases.exists?

        product.destroy!
      end
    end

    def report(item_moves, alias_moves, unfilled)
      @io.puts(@dry_run ? "DRY RUN — nothing is written. DRY_RUN=0 applies it." : "Applying.")
      @io.puts("#{unfilled} items get their original key recorded.") if unfilled.positive?
      @io.puts("Nothing to move.") if item_moves.empty? && alias_moves.empty?
      item_moves.sort_by { |m| [ m.to, m.from.to_s ] }.each do |move|
        @io.puts("#{move.from || '(no product)'} (#{move.ids.size} items) -> #{move.to}")
      end
      alias_moves.sort_by { |m| [ m.to, m.from ] }.each do |move|
        @io.puts("#{move.from} (#{move.ids.size} dictionary entries) -> #{move.to}")
      end
    end
  end
end
