class AddAmountLeftToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :amount_left, :float, default: 1.0, null: false
  end
end
