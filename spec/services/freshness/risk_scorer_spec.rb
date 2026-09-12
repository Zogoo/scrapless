require "rails_helper"

RSpec.describe Freshness::RiskScorer do
  before do
    create(:shelf_life_rule, category: "produce", storage: "fridge",
                             days_p50: 5, days_p90: 9, consume_p50: 5)
  end

  let(:household) { create(:household) }

  it "scores nothing on the day of the shop" do
    item = create(:item, household: household)
    scored = described_class.call(items: [ item ]).first

    expect(scored.spoilage).to eq(0.0)
    expect(scored.risk).to eq(0.0)
    expect(scored.phase).to eq("fresh")
  end

  # This is the correction that the whole model exists for. Both items are the
  # same age; the one bought long ago and eaten weekly should not outrank the one
  # that is genuinely about to go off.
  it "will not alert about food that has probably already been eaten" do
    old = create(:item, :ghost, household: household)
    scored = described_class.call(items: [ old ]).first

    expect(scored.spoilage).to eq(1.0)
    expect(scored.alertable?).to be(false),
      "spoilage alone would alert here; presence has to veto it"
  end

  it "alerts in the window where the answer is still actionable" do
    item = create(:item, :at_risk, household: household)
    scored = described_class.call(items: [ item ]).first

    expect(scored.alertable?).to be(true)
    expect(scored.phase).to eq("at_risk")
  end

  it "ranks by risk, not by age" do
    fresh = create(:item, household: household, display_name: "Fresh")
    risky = create(:item, :at_risk, household: household, display_name: "Risky")

    expect(described_class.call(items: [ fresh, risky ]).map { |s| s.item.display_name })
      .to eq(%w[Risky Fresh])
  end

  it "only asks about an item in the sweep once the answer would change something" do
    young = create(:item, household: household, acquired_on: Date.current - 4,
                          window_start: Date.current, window_end: Date.current + 5)
    scored = described_class.call(items: [ young ]).first

    expect(scored.presence).to be_between(0.25, 0.6),
      "this example is only meaningful while presence sits in the ambiguous band"
    expect(scored.ambiguous?).to be(false), "too early in its life to be worth a question"
  end
end
