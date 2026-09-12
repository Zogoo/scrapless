require "rails_helper"

RSpec.describe Memo::Suggester do
  let(:household) { create(:household) }

  it "falls back to staples for a fridge with no history" do
    names = described_class.call(household: household).map(&:name)

    expect(names).to include("Milk", "Bread")
  end

  # The suggestion worth having: bought on a rhythm, and now overdue. It costs
  # the user nothing to provide and no model call to compute.
  it "surfaces something the household buys regularly and is now out of" do
    [ 21, 14, 7 ].each do |days_ago|
      create(:item, household: household, canonical_name: "milch",
                    acquired_on: Date.current - days_ago)
    end

    top = described_class.call(household: household).first

    expect(top.name).to eq("Milch")
    expect(top.reason).to match(/usually every 7 days/)
  end

  it "does not suggest what is already on the memo" do
    create(:memo_item, household: household, name: "Milk")

    expect(described_class.call(household: household).map(&:name)).not_to include("Milk")
  end

  it "filters by the query as the user types" do
    names = described_class.call(household: household, query: "brea").map(&:name)

    expect(names).to eq([ "Bread" ])
  end

  # What someone has started typing beats what they bought last month.
  it "puts a prefix match above a higher-scoring substring match" do
    create(:item, household: household, canonical_name: "broccoli", acquired_on: Date.current)

    names = described_class.call(household: household, query: "co").map(&:name)

    expect(names.first).to eq("Coffee")
    expect(names).to include("Broccoli")
  end
end
