require "rails_helper"

RSpec.describe Notifications::Compose do
  let(:household) { create(:household) }

  before do
    create(:shelf_life_rule, category: "produce", storage: "fridge", days_p50: 5, days_p90: 9, consume_p50: 5)
  end

  def compose = described_class.call(household: household).map(&:item)

  it "picks food that is going off and probably still here" do
    at_risk = create(:item, :at_risk, household: household)
    create(:item, household: household) # bought today

    expect(compose).to eq([ at_risk ])
  end

  # CLAUDE.md rule 2: spoilage alone would pick this; presence vetoes it.
  it "says nothing about food that has probably been eaten" do
    create(:item, :ghost, household: household)

    expect(compose).to be_empty
  end

  it "respects a 'not now' until the snooze ends" do
    create(:item, :at_risk, household: household, snoozed_until: Date.current + 1)

    expect(compose).to be_empty
  end

  it "names at most two foods" do
    create_list(:item, 3, :at_risk, household: household)

    expect(compose.size).to eq(2)
  end

  it "never looks at another kitchen's food" do
    create(:item, :at_risk, household: create(:household))

    expect(compose).to be_empty
  end
end
