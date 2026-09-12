require "rails_helper"

RSpec.describe Captures::Ingest do
  before do
    create(:shelf_life_rule, category: "produce", storage: "fridge",
                             days_p50: 5, days_p90: 9, consume_p50: 5)
    create(:shelf_life_rule, category: "dairy", storage: "fridge",
                             days_p50: 8, days_p90: 14, consume_p50: 6)
    create(:product_alias, raw_text: "brokkoli", canonical_name: "Brokkoli",
                           category: "produce", emoji: "🥦")
  end

  let(:household) { create(:household) }
  let(:capture) { create(:capture, household: household) }

  def payload(lines)
    { "merchant" => "REWE", "purchased_on" => Date.current.iso8601, "lines" => lines }
  end

  it "creates an item per food line, with a window on each" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "BROKKOLI", "name" => "Brokkoli", "quantity" => 1, "food" => true },
      { "raw_text" => "H-MILCH 3,5%", "name" => "Milch", "quantity" => 1, "food" => true }
    ]))

    expect(result[:items].size).to eq(2)
    expect(result[:items].map(&:window_end)).to all(be_present)
    expect(capture.reload.status).to eq("parsed")
    expect(capture.merchant).to eq("REWE")
  end

  # Proving we filtered the deposit line is what makes the parser trustworthy,
  # so suppressed lines are returned to the review screen, not silently dropped.
  it "suppresses non-food lines and reports what it suppressed" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "BROKKOLI", "name" => "Brokkoli", "food" => true },
      { "raw_text" => "PFAND 0,25", "name" => "Pfand", "food" => true },
      { "raw_text" => "TRAGETASCHE", "name" => "Tasche", "food" => false }
    ]))

    expect(result[:items].size).to eq(1)
    expect(result[:suppressed]).to contain_exactly("PFAND 0,25", "TRAGETASCHE")
  end

  it "uses the dictionary in preference to the model's own naming" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "BROKKOLI", "name" => "Green Vegetable Thing", "food" => true }
    ]))

    expect(result[:items].first.display_name).to include("Brokkoli")
  end

  # Never block on a partial failure: a capture that refuses to finish is a
  # capture the user stops making.
  it "keeps the lines it understood when others are unusable" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "BROKKOLI", "name" => "Brokkoli", "food" => true },
      { "raw_text" => nil, "name" => nil, "food" => true }
    ]))

    expect(result[:items].size).to eq(1)
    expect(capture.reload.status).to eq("parsed")
    expect(capture.parse_confidence).to eq(0.5)
  end

  it "marks a capture failed when nothing survived, without raising" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "PFAND 0,25", "name" => "Pfand", "food" => true }
    ]))

    expect(result[:items]).to be_empty
    expect(capture.reload.status).to eq("failed")
  end

  it "logs a captured event for every item, as training data" do
    described_class.call(capture: capture, payload: payload([
      { "raw_text" => "BROKKOLI", "name" => "Brokkoli", "food" => true }
    ]))

    expect(household.item_events.where(kind: "captured").count).to eq(1)
  end

  it "backdates the window to the day the shop happened, not the day it was uploaded" do
    result = described_class.call(capture: capture, payload: {
      "purchased_on" => (Date.current - 3).iso8601,
      "lines" => [ { "raw_text" => "BROKKOLI", "name" => "Brokkoli", "food" => true } ]
    })

    expect(result[:items].first.acquired_on).to eq(Date.current - 3)
    expect(result[:items].first.window_end).to eq(Date.current + 6)
  end
end
