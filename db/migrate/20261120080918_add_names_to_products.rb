class AddNamesToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :names, :json, default: {}, null: false
  end
end
