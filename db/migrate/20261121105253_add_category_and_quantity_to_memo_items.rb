class AddCategoryAndQuantityToMemoItems < ActiveRecord::Migration[8.1]
  def up
    add_column :memo_items, :category, :string, default: "other", null: false
    add_column :memo_items, :quantity, :integer, default: 1, null: false

    # Lines already on lists get their store section now; the rake task
    # memo:backfill_categories can rerun it (DRY_RUN=1 first).
    MemoItem.reset_column_information
    Memo::BackfillCategories.call(dry_run: false, io: StringIO.new)
  end

  def down
    remove_column :memo_items, :quantity
    remove_column :memo_items, :category
  end
end
