class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :key, null: false

      t.timestamps
    end
    add_index :products, :key, unique: true
  end
end
