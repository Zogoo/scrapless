class AddCheckedOnToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :checked_on, :date
  end
end
