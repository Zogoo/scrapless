class AddProductToProductAliases < ActiveRecord::Migration[8.1]
  def change
    add_reference :product_aliases, :product, foreign_key: true
    # Where the entry came from: seed, correction, ai or promoted. Provenance is
    # what lets a bad batch be found and rolled back (doc 5 §5.6).
    add_column :product_aliases, :source, :string, null: false, default: "correction"
    # Promotion counts kitchens per spelling across every household.
    add_index :product_aliases, %i[raw_text merchant]

    up_only { execute "UPDATE product_aliases SET source = 'seed' WHERE seeded = 1" }
  end
end
