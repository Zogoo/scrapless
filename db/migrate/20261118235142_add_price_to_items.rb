# The total printed on an item's receipt line, in its capture's currency.
# Savings printed under it stay discount rows (Capture#raw_payload) and the
# receipt's total says what was paid. Scale 3 fits every ISO 4217 minor unit.
class AddPriceToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :price, :decimal, precision: 12, scale: 3
  end
end
