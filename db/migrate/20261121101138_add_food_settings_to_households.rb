class AddFoodSettingsToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :brotbox_count, :integer
    add_column :households, :diet, :string
    add_column :households, :excluded_foods, :json, default: [], null: false
  end
end
