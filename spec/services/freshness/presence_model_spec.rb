require "rails_helper"

RSpec.describe Freshness::PresenceModel do
  before do
    create(:shelf_life_rule, category: "produce", storage: "fridge",
                             days_p50: 5, days_p90: 9, consume_p50: 5)
  end

  let(:household) { create(:household) }
  let(:item) { create(:item, household: household, acquired_on: Date.current) }

  it "is certain on the day of the shop" do
    expect(described_class.call(item: item)).to eq(1.0)
  end

  it "is a half-life: even odds at exactly the consumption cadence" do
    expect(described_class.call(item: item, on: Date.current + 5)).to be_within(0.02).of(0.5)
  end

  it "decays without ever reaching zero, because leftovers linger" do
    expect(described_class.call(item: item, on: Date.current + 40)).to be > 0
  end

  # The whole point of R4b: the household's own repurchase rhythm beats the
  # global table, and it arrives free with every receipt.
  context "when the household has a repurchase history" do
    it "prefers its own cadence over the category default" do
      [ 20, 18, 16, 14 ].each do |days_ago|
        create(:item, household: household, canonical_name: "brokkoli",
                      acquired_on: Date.current - days_ago)
      end

      # Bought every 2 days here, against a 5-day category default, so a 2-day-old
      # broccoli is far likelier to be gone than the global table would say.
      own = described_class.call(item: item, on: Date.current + 2)
      expect(own).to be_within(0.02).of(0.5)
    end

    it "ignores a history too short to have a median" do
      create(:item, household: household, canonical_name: "brokkoli",
                    acquired_on: Date.current - 3)

      expect(described_class.call(item: item, on: Date.current + 5)).to be_within(0.02).of(0.5)
    end
  end
end
