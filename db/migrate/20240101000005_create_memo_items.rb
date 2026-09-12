class CreateMemoItems < ActiveRecord::Migration[8.1]
  def change
    create_table :memo_items do |t|
      t.references :household, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :canonical_name
      t.string  :note
      # voice | text | suggestion | auto
      t.string  :source, null: false, default: "text"
      t.boolean :done, null: false, default: false
      t.datetime :done_at
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :memo_items, %i[household_id done position]
  end
end
