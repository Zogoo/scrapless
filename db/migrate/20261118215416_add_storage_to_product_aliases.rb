class AddStorageToProductAliases < ActiveRecord::Migration[8.1]
  def change
    add_column :product_aliases, :storage, :string
  end
end
