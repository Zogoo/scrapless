# Notifications a week this kitchen accepts: 0 (off) to 3, default 1 (doc 3 R5).
class AddAlertsPerWeekToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :alerts_per_week, :integer, null: false, default: 1
  end
end
