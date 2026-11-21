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

  it "issues a join code that is not the bearer token" do
    household = described_class.create!

    expect(household.join_code).to be_present
    expect(household.join_code).not_to eq(household.token)
  end

  describe "food settings" do
    it "allows every setting to be unanswered" do
      expect(described_class.new(brotbox_count: nil, diet: nil, excluded_foods: [])).to be_valid
    end

    it "takes a Brotbox count from 0 to 6, and nothing outside it" do
      expect(described_class.new(brotbox_count: 0)).to be_valid
      expect(described_class.new(brotbox_count: 6)).to be_valid
      expect(described_class.new(brotbox_count: 7)).not_to be_valid
      expect(described_class.new(brotbox_count: -1)).not_to be_valid
    end

    it "knows three ways of eating" do
      expect(described_class::DIETS.map { |diet| described_class.new(diet: diet) }).to all(be_valid)
      expect(described_class.new(diet: "keto")).not_to be_valid
    end

    it "keeps foods to leave out stripped and once each, whatever the case" do
      household = described_class.new(excluded_foods: [ " Nüsse ", "nüsse", "", "Schwein" ])

      expect(household.excluded_foods).to eq(%w[Nüsse Schwein])
    end

    it "keeps the list short and each entry short" do
      expect(described_class.new(excluded_foods: (1..21).map { |n| "Essen #{n}" })).not_to be_valid
      expect(described_class.new(excluded_foods: [ "x" * 41 ])).not_to be_valid
      expect(described_class.new(excluded_foods: [ "x" * 40 ])).to be_valid
    end
  end
end
