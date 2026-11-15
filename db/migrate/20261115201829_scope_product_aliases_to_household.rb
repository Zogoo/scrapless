# A correction belongs to the kitchen that made it (doc 5 §5.6). Rows with no
# household are the shared, seeded dictionary, which no anonymous fridge may
# overwrite.
class ScopeProductAliasesToHousehold < ActiveRecord::Migration[8.1]
  def change
    add_reference :product_aliases, :household, null: true, foreign_key: true

    remove_index :product_aliases, %i[raw_text merchant], unique: true,
                 name: "index_product_aliases_on_raw_text_and_merchant"
    add_index :product_aliases, %i[household_id raw_text merchant], unique: true,
              name: "index_product_aliases_on_household_raw_text_merchant"
  end
end
