# "Stop suggesting this." One row per kitchen and name: a junk line from one bad
# capture used to become a permanent Shop suggestion with no way to remove it.
class CreateSuggestionDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :suggestion_dismissals do |t|
      t.references :household, null: false, foreign_key: true
      t.string :canonical_name, null: false

      t.timestamps
    end
    add_index :suggestion_dismissals, %i[household_id canonical_name], unique: true
  end
end
