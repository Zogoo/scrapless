# The notification budget (doc 5 §5.5). The cap is an invariant, so it lives in
# unique indexes rather than in a counter: at most one notification per kitchen
# per day, and slot n of week w can be spent once. A repeated tick, or two
# ticks at once, cannot send twice.
class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :household, null: false, foreign_key: true
      t.string :iso_week, null: false
      t.integer :slot, null: false
      t.date :sent_on, null: false
      t.json :item_ids, null: false, default: []
      t.datetime :opened_at

      t.timestamps
    end
    add_index :notifications, %i[household_id iso_week slot], unique: true
    add_index :notifications, %i[household_id sent_on], unique: true
  end
end
