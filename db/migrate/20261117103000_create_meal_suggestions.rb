# One stored answer per kitchen, meal and day. A second tap shows this row
# instead of calling the model again, and a restart must not forget it.
class CreateMealSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :meal_suggestions do |t|
      t.references :household, null: false, foreign_key: true
      t.string :meal, null: false
      t.date :served_on, null: false
      t.string :locale, null: false
      t.text :body, null: false

      t.timestamps
    end

    add_index :meal_suggestions, %i[household_id meal served_on],
              unique: true, name: "index_meal_suggestions_on_household_meal_and_day"
  end
end
