class CreateItemEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :item_events do |t|
      t.references :item, null: false, foreign_key: true
      t.references :household, null: false, foreign_key: true
      # captured | used | partial_use | wasted | frozen | opened | snoozed | corrected | retired
      t.string   :kind, null: false
      t.datetime :at,   null: false
      t.text     :meta

      t.timestamps
    end

    add_index :item_events, %i[household_id kind at]
  end
end
