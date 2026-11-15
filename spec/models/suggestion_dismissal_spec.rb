require "rails_helper"

RSpec.describe SuggestionDismissal do
  it "stores the name the way suggestions are matched" do
    expect(create(:suggestion_dismissal, canonical_name: "  Thing17 ").canonical_name).to eq("thing17")
  end

  it "holds one row per kitchen and name" do
    first = create(:suggestion_dismissal)

    expect(build(:suggestion_dismissal, household: first.household)).not_to be_valid
    expect(build(:suggestion_dismissal)).to be_valid
  end
end
