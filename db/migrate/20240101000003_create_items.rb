class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.references :household, null: false, foreign_key: true
      t.references :capture, foreign_key: true

      t.string  :display_name,   null: false
      t.string  :canonical_name, null: false
      t.string  :category,       null: false, default: "unknown"
      # Verbatim source text — the only provenance a VLM gives us (doc 5).
      t.string  :raw_text

      t.decimal :quantity, precision: 8, scale: 2
      t.string  :unit
      t.float   :quantity_confidence

      # fridge | freezer | pantry
      t.string  :storage, null: false, default: "fridge"
      t.datetime :storage_changed_at

      t.date  :acquired_on, null: false
      # A window, never a single expires_on: the schema forbids fake precision.
      t.date  :window_start, null: false
      t.date  :window_end,   null: false
      t.float :confidence,   null: false, default: 0.3

      t.date   :opened_on
      # none | mhd (quality, may extend) | verbrauchsdatum (safety, never extends)
      t.string :date_label_type, null: false, default: "none"
      t.date   :date_label_value

      # active | rescued | wasted | retired
      t.string   :state, null: false, default: "active"
      t.datetime :resolved_at
      t.date     :snoozed_until

      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    add_index :items, %i[household_id state window_end]
    add_index :items, %i[household_id canonical_name]
  end
end
