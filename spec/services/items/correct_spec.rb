require "rails_helper"

RSpec.describe Items::Correct do
  let(:household) { create(:household) }

  before do
    create(:shelf_life_rule, category: "dairy", storage: "fridge", days_p50: 8, days_p90: 14)
    create(:shelf_life_rule, category: "bakery", storage: "fridge", days_p50: 5, days_p90: 8)
    create(:shelf_life_rule, category: "dairy", storage: "freezer", days_p50: 60, days_p90: 90)
  end

  # Observed live: "WEIZENBRÖTCHEN" filed as dairy got a 14-day fridge window,
  # and renaming it in the Kitchen fixed the label but not the window.
  def misfiled_bread
    create(:item, household: household, raw_text: "WEIZENBROETCHEN 6ER", display_name: "Weizenbroetchen",
                  canonical_name: "weizenbroetchen", category: "dairy", acquired_on: Date.current,
                  window_start: Date.current + 6, window_end: Date.current + 14)
  end

  it "re-reads the category from a new name and re-dates the food" do
    item = described_class.call(item: misfiled_bread,
                                changes: { display_name: "Bread rolls", canonical_name: "bread rolls" })

    expect(item.category).to eq("bakery")
    expect(item.window_end).to eq(Date.current + 8)
  end

  it "teaches the dictionary the corrected category, not the old one" do
    described_class.call(item: misfiled_bread,
                         changes: { display_name: "Bread rolls", canonical_name: "bread rolls" })

    entry = ProductAlias.lookup("WEIZENBROETCHEN 6ER", household: household)
    expect(entry).to have_attributes(canonical_name: "bread rolls", category: "bakery")
  end

  it "keeps the category when the new name tells it nothing" do
    item = described_class.call(item: misfiled_bread, changes: { display_name: "Grandma's thing" })

    expect(item.category).to eq("dairy")
    expect(item.window_end).to eq(Date.current + 14)
  end

  it "takes a category the client sent over its own guess" do
    item = described_class.call(item: misfiled_bread, changes: { display_name: "Bread", category: "dairy" })

    expect(item.category).to eq("dairy")
  end

  # A move restarts the clock for the new place; it is not the old window.
  it "re-dates from today when the food moves" do
    item = create(:item, household: household, category: "dairy", acquired_on: Date.current - 5)

    item = described_class.call(item: item, changes: { storage: "freezer" })

    expect(item.window_end).to eq(Date.current + 90)
    expect(item.storage_changed_at).to be_present
  end

  it "lets a printed safety date win and never extends it" do
    item = create(:item, household: household, category: "dairy")

    item = described_class.call(item: item, changes: { date_label_type: "verbrauchsdatum",
                                                       date_label_value: (Date.current + 2).iso8601 })

    expect(item.window_end).to eq(Date.current + 2)
    expect(item.high_risk?).to be(true)
  end

  it "leaves the window alone when nothing it depends on changed" do
    item = create(:item, household: household, window_end: Date.current + 9)

    item = described_class.call(item: item, changes: { quantity: 2 })

    expect(item.window_end).to eq(Date.current + 9)
  end

  it "records what changed" do
    item = described_class.call(item: misfiled_bread, changes: { display_name: "Bread rolls" })

    expect(item.item_events.last.meta_payload["changed"]).to include("display_name", "category", "window_end")
  end
end
