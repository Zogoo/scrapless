class CreateCaptures < ActiveRecord::Migration[8.1]
  def change
    create_table :captures do |t|
      t.references :household, null: false, foreign_key: true
      # receipt | shelf_photo | voice | text | grid
      t.string  :source,   null: false
      # pending | parsed | failed
      t.string  :status,   null: false, default: "pending"
      t.string  :merchant
      t.date    :purchased_on
      # Derived from checksums (doc 12), never vendor-reported.
      t.float   :parse_confidence
      t.text    :transcript
      t.text    :raw_response
      t.string  :error_message
      t.integer :line_count, null: false, default: 0

      t.timestamps
    end

    add_index :captures, %i[household_id created_at]
  end
end
