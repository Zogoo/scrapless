class AddProductToItems < ActiveRecord::Migration[8.1]
  def change
    add_reference :items, :product, foreign_key: true
  end
end
