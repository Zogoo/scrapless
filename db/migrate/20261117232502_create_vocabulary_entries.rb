class CreateVocabularyEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :vocabulary_entries do |t|
      t.references :household, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :phrase, null: false

      t.timestamps
    end
    add_index :vocabulary_entries, %i[household_id kind phrase], unique: true
  end
end
