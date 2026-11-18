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

  # The slider's open rebuilt the window from the category table and then
  # capped it, so a pack due tomorrow and a pack due in two weeks both became
  # "3 days". The cap applies only when it is sooner than the end already there.
  it "keeps an end that is sooner than the opened cap, and undo puts the dates back" do
    milk = create(:item, household: household, category: "dairy", acquired_on: Date.current - 10,
                         window_start: Date.current - 4, window_end: Date.current + 1)
    was = [ milk.window_start, milk.window_end ]

    described_class.call(item: milk, outcome: "opened")

    expect(milk.reload).to have_attributes(opened_on: Date.current, window_end: was[1])

    Items::Undo.call(item: milk)

    expect(milk.reload).to have_attributes(opened_on: nil, window_start: was[0], window_end: was[1])
  end

  it "does not rewrite the dates of a pack that is already open" do
    milk = create(:item, household: household, category: "dairy", opened_on: Date.current - 2,
                         window_start: Date.current - 2, window_end: Date.current + 1)

    described_class.call(item: milk, outcome: "opened")

    expect(milk.reload).to have_attributes(opened_on: Date.current - 2, window_end: Date.current + 1)
  end

  it "records a half-used pack as half wasted, not a whole pack" do
    item = create(:item, household: household, amount_left: 0.5, quantity: 1)

    described_class.call(item: item, outcome: "wasted")

    expect(item.reload).to have_attributes(state: "wasted", amount_left: 0.5)
    expect(item.quantity.to_f).to eq(0.5)
    expect(item.item_events.last.meta_payload["amount"]).to eq(0.5)
  end

  it "records an untouched pack as one wasted" do
    item = create(:item, household: household, amount_left: 1)

    described_class.call(item: item, outcome: "wasted")

    expect(item.reload.quantity.to_f).to eq(1)
    expect(item.item_events.last.meta_payload["amount"]).to eq(1)
  end

  it "records the item as it was, so the tap can be undone" do
    item = create(:item, household: household)

    described_class.call(item: item, outcome: "wasted")

    before = item.item_events.last.meta_payload["before"]
    expect(before).to include("state" => "active")
  end

  describe "moving food somewhere else" do
    it "keeps the days already spent when bread goes from the fridge to the cupboard" do
      bread = create(:item, household: household, category: "bakery", acquired_on: Date.current - 3)

      described_class.call(item: bread, outcome: "moved", to: "pantry")

      expect(bread.reload).to have_attributes(storage: "pantry", acquired_on: Date.current - 3)
      expect(bread.storage_changed_at).to be_present
      expect(bread.window_start).to be >= bread.acquired_on
      expect(bread.item_events.last.kind).to eq("moved")
    end

    # Observed in QA: milk moved to the cupboard read "fine for about 6 months",
    # the cupboard's generic window, because there is no dairy-in-cupboard rule.
    it "never gives food more time for moving it out of the fridge" do
      milk = create(:item, household: household, category: "dairy", window_end: Date.current + 9)

      described_class.call(item: milk, outcome: "moved", to: "pantry")

      expect(milk.reload.window_end).to be <= Date.current + 9
      expect(milk.window_start).to be <= milk.window_end
    end

    it "treats a move into the freezer as freezing it" do
      milk = create(:item, household: household, category: "dairy")

      described_class.call(item: milk, outcome: "moved", to: "freezer")

      expect(milk.reload.storage).to eq("freezer")
      expect(milk.window_end).to be > Date.current + 100
      expect(milk.item_events.last.kind).to eq("frozen")
    end

    it "gives food out of the freezer a thawed window, not a fresh one" do
      chicken = create(:item, household: household, category: "meat_fish", storage: "freezer",
                              acquired_on: Date.current - 60, window_end: Date.current + 200)

      described_class.call(item: chicken, outcome: "moved", to: "fridge")

      expect(chicken.reload).to have_attributes(storage: "fridge", window_end: Date.current + 2)
    end

    it "can be undone back to where it was" do
      bread = create(:item, household: household, category: "bakery")
      window = [ bread.window_start, bread.window_end ]

      described_class.call(item: bread, outcome: "moved", to: "freezer")
      Items::Undo.call(item: bread)

      expect(bread.reload).to have_attributes(storage: "fridge", window_start: window[0], window_end: window[1])
    end

    it "refuses a place that does not exist, or the one it is already in" do
      bread = create(:item, household: household)

      expect { described_class.call(item: bread, outcome: "moved", to: "garage") }
        .to raise_error(described_class::UnknownOutcome)
      expect { described_class.call(item: bread, outcome: "moved", to: "fridge") }
        .to raise_error(described_class::UnknownOutcome)
    end
  end

  it "refuses an outcome it does not know, without calling anything by that name" do
    expect { described_class.call(item: create(:item, household: household), outcome: "destroy") }
      .to raise_error(described_class::UnknownOutcome)
  end
end
