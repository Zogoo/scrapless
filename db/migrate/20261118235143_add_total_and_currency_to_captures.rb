# The receipt's printed total, and the ISO 4217 currency its prices are in.
class AddTotalAndCurrencyToCaptures < ActiveRecord::Migration[8.1]
  def change
    add_column :captures, :total, :decimal, precision: 12, scale: 3
    add_column :captures, :currency, :string, limit: 3
  end
end
