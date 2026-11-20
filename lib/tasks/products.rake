namespace :products do
  desc "Put items and dictionary entries on the products config/product_merge.yml says (DRY_RUN=1 by default)"
  task recompute_merges: :environment do
    Products::RecomputeMerges.call(dry_run: ENV.fetch("DRY_RUN", "1") != "0")
  end
end
