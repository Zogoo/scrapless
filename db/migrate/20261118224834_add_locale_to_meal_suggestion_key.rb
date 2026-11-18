# One cached recipe per kitchen, meal, day *and language*: a German phone asked
# after an English one was served the English recipe until midnight.
class AddLocaleToMealSuggestionKey < ActiveRecord::Migration[8.1]
  def change
    remove_index :meal_suggestions, %i[household_id meal served_on],
                 name: "index_meal_suggestions_on_household_meal_and_day", unique: true
    add_index :meal_suggestions, %i[household_id meal served_on locale],
              name: "index_meal_suggestions_on_household_meal_day_locale", unique: true
  end
end
