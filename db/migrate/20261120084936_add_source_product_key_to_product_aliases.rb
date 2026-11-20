class AddSourceProductKeyToProductAliases < ActiveRecord::Migration[8.1]
  def change
    add_column :product_aliases, :source_product_key, :string
    add_index :product_aliases, :source_product_key
  end
end
