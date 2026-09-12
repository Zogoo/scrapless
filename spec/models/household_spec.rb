require "rails_helper"

RSpec.describe Household do
  it "issues its own identity, because there is no sign-up form to collect one" do
    household = described_class.create!

    expect(household.uuid).to be_present
    expect(household.token).to be_present
    expect(household.name).to be_present
  end

  it "gives an unnamed fridge a name someone would recognise in a list" do
    # [[:alpha:]] rather than \w: the noun list contains "Kombüse", and \w
    # is ASCII-only, so this example failed roughly one run in eight.
    expect(described_class.create!.name).to match(/\A[[:alpha:]]+ [[:alpha:]]+\z/)
  end

  it "keeps a name the user chose" do
    expect(described_class.create!(name: "Küche").name).to eq("Küche")
  end

  it "issues a different token to every fridge" do
    expect(described_class.create!.token).not_to eq(described_class.create!.token)
  end
end
