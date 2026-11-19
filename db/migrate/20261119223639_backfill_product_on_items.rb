class BackfillProductOnItems < ActiveRecord::Migration[8.1]
  # Data only: items from before products existed get theirs, so the Kitchen
  # stops showing the same food twice (Items::BackfillProducts). Nothing to
  # undo; a product on an item is always allowed to be there.
  def up
    Items::BackfillProducts.call
  end

  def down; end
end
