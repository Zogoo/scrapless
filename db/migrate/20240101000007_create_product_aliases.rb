class CreateProductAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :product_aliases do |t|
      # Lowercased receipt jargon, e.g. "gurk.sal.stck".
      t.string  :raw_text,       null: false
      t.string  :canonical_name, null: false
      t.string  :category,       null: false
      t.string  :merchant
      t.string  :emoji
      # How often anyone has confirmed this mapping — the compounding asset.
      t.integer :votes, null: false, default: 1
      t.boolean :seeded, null: false, default: false

      t.timestamps
    end

    add_index :product_aliases, %i[raw_text merchant], unique: true
    add_index :product_aliases, :canonical_name
  end
end
