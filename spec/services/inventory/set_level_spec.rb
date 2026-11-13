require "rails_helper"

RSpec.describe Inventory::SetLevel do
  let(:household) { create(:household) }
  let!(:old_milk) do
    create(:item, household: household, display_name: "Milch", canonical_name: "milch",
                  acquired_on: Date.current - 5, window_start: Date.current, window_end: Date.current + 2)
  end
  let!(:new_milk) do
    create(:item, household: household, display_name: "Milch", canonical_name: "milch",
                  acquired_on: Date.current, window_start: Date.current + 5, window_end: Date.current + 8)
  end
  let(:ids) { [ old_milk.id, new_milk.id ] }

  it "drains the pack that dies soonest first" do
    described_class.call(household: household, ids: ids, level: 1.5)

    expect(old_milk.reload.amount_left).to eq(0.5)
    expect(new_milk.reload.amount_left).to eq(1.0)
  end

  it "treats a pack slid to empty as used, not deleted" do
    remaining = described_class.call(household: household, ids: ids, level: 0.75)

    expect(old_milk.reload.state).to eq("rescued")
    expect(old_milk.item_events.last.kind).to eq("used")
    expect(new_milk.reload.amount_left).to eq(0.75)
    expect(remaining).to eq([ new_milk ])
  end

  it "fills back freshest-first when the slider goes up" do
    old_milk.update!(amount_left: 0.2)

    described_class.call(household: household, ids: ids, level: 2)

    expect([ old_milk.reload.amount_left, new_milk.reload.amount_left ]).to eq([ 1.0, 1.0 ])
  end

  it "cannot set more than there are packs" do
    described_class.call(household: household, ids: ids, level: 9)

    expect(household.items.active.count).to eq(2)
    expect(old_milk.reload.amount_left).to eq(1.0)
  end

  # Display only: the slider must not move the alert maths (CLAUDE.md rule 2 is
  # owned by the presence model and partial_use events).
  it "leaves P(still present) alone" do
    before = Freshness::PresenceModel.call(item: new_milk)

    described_class.call(household: household, ids: ids, level: 0.5)

    expect(Freshness::PresenceModel.call(item: new_milk.reload)).to eq(before)
  end

  it "ignores another fridge's ids" do
    foreign = create(:item, household: create(:household))

    described_class.call(household: household, ids: [ foreign.id ], level: 0)

    expect(foreign.reload.state).to eq("active")
  end
end
