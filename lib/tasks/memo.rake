namespace :memo do
  desc "Give shopping lines their store section (DRY_RUN=1 by default)"
  task backfill_categories: :environment do
    Memo::BackfillCategories.call(dry_run: ENV.fetch("DRY_RUN", "1") != "0")
  end
end
