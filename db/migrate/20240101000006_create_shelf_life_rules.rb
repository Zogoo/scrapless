class CreateShelfLifeRules < ActiveRecord::Migration[8.1]
  def change
    create_table :shelf_life_rules do |t|
      t.string  :category, null: false
      t.string  :storage,  null: false
      t.integer :days_p50, null: false
      t.integer :days_p90, null: false
      # Typical days until a household has eaten it — the presence signal,
      # which is a different curve from spoilage (doc 5 §5.4b).
      t.integer :consume_p50, null: false
      t.boolean :high_risk, null: false, default: false

      t.timestamps
    end

    add_index :shelf_life_rules, %i[category storage], unique: true
  end
end
