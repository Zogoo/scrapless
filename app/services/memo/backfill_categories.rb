module Memo
  # Gives every shopping line its store section (Memo::CategoryFor), for lines
  # written before sections existed. Rerunnable: `rake memo:backfill_categories`
  # (DRY_RUN=1 by default) reports what would change and writes nothing.
  class BackfillCategories < ApplicationService
    def initialize(dry_run: true, io: $stdout)
      @dry_run = dry_run
      @io = io
    end

    def call
      changes = Hash.new(0)
      Household.where(id: MemoItem.select(:household_id)).find_each do |household|
        resolver = CategoryFor.new(household: household)
        household.memo_items.find_each do |line|
          category = resolver.call(line.name)
          next if category == line.category

          changes[category] += 1
          line.update_columns(category: category) unless @dry_run
        end
      end
      report(changes)
      changes
    end

    private

    def report(changes)
      @io.puts(@dry_run ? "DRY RUN — nothing is written. DRY_RUN=0 applies it." : "Applying.")
      @io.puts("Nothing to change.") if changes.empty?
      changes.sort.each { |category, count| @io.puts("#{count} lines -> #{category}") }
    end
  end
end
