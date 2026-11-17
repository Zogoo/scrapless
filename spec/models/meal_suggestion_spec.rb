require "rails_helper"

RSpec.describe MealSuggestion do
  it "holds one meal per kitchen per day" do
    first = create(:meal_suggestion)

    expect(build(:meal_suggestion, household: first.household, meal: first.meal,
                                   served_on: first.served_on)).not_to be_valid
    expect(build(:meal_suggestion, household: first.household, meal: "breakfast")).to be_valid
    expect(build(:meal_suggestion, household: first.household, served_on: Date.current + 1)).to be_valid
    expect(build(:meal_suggestion, meal: first.meal, served_on: first.served_on)).to be_valid
  end
end
