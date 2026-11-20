class AddSourceProductKeyToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :source_product_key, :string
    add_index :items, :source_product_key
  end
end
