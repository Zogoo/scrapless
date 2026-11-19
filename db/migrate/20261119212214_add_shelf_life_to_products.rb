class AddShelfLifeToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :shelf_life, :json
  end
end
