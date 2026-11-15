require "rails_helper"

RSpec.describe Items::Resolve do
  let(:household) { create(:household) }

  before { create(:shelf_life_rule, category: "dairy", storage: "fridge", days_p50: 8, days_p90: 14) }

  # Observed in QA: "Opened it" on milk bought today returned 422, because the
  # window's end moved to opened+3 while its start stayed at bought+6.
  it "opens food whose window has not started yet" do
    milk = create(:item, household: household, category: "dairy", acquired_on: Date.current,
                         window_start: Date.current + 6, window_end: Date.current + 14)

    described_class.call(item: milk, outcome: "opened")

    expect(milk.reload).to have_attributes(opened_on: Date.current, window_end: Date.current + 3)
    expect(milk.window_start).to be <= milk.window_end
  end

  it "records the item as it was, so the tap can be undone" do
    item = create(:item, household: household)

    described_class.call(item: item, outcome: "wasted")

    before = item.item_events.last.meta_payload["before"]
    expect(before).to include("state" => "active")
  end

  it "refuses an outcome it does not know, without calling anything by that name" do
    expect { described_class.call(item: create(:item, household: household), outcome: "destroy") }
      .to raise_error(described_class::UnknownOutcome)
  end
end
