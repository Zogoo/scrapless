require "rails_helper"

RSpec.describe Items::RevertSliderOpen do
  let(:household) { create(:household) }

  # Unopened produce keeps the category's long end (about 9 days in the fridge).
  # The first slider move opens it and the end comes in to 3. Coming back to
  # the percent that drag started at undoes that open, even after the open was
  # saved and a level change landed on top of it.
  it "restores the 9-day window when a later release is back at the start percent" do
    potato = create(:item, household: household, category: "produce", display_name: "Potato",
                           canonical_name: "potato", acquired_on: Date.current,
                           window_start: Date.current + 4, window_end: Date.current + 9)

    Items::Resolve.call(item: potato, outcome: "opened", source: "slider", start_percent: 100)

    expect(potato.reload).to have_attributes(opened_on: Date.current, window_end: Date.current + 3)

    Inventory::SetLevel.call(household: household, ids: [ potato.id ], level: 0.5)
    expect { Items::Undo.call(item: potato) }.to raise_error(Items::Undo::NotUndoable)

    described_class.call(item: potato.reload, percent: 100)

    expect(potato.reload).to have_attributes(opened_on: nil, window_start: Date.current + 4,
                                             window_end: Date.current + 9, amount_left: 0.5)
    expect(potato.item_events.where(kind: "opened")).to be_empty
  end

  it "leaves the opened window when the release is not the percent the open started at" do
    potato = create(:item, household: household, category: "produce", acquired_on: Date.current,
                           window_start: Date.current + 4, window_end: Date.current + 9)
    Items::Resolve.call(item: potato, outcome: "opened", source: "slider", start_percent: 100)

    described_class.call(item: potato.reload, percent: 50)

    expect(potato.reload).to have_attributes(opened_on: Date.current, window_end: Date.current + 3)
  end

  it "does not clear a pack that was already open before the slider" do
    potato = create(:item, household: household, category: "produce", opened_on: Date.current - 2,
                           window_start: Date.current - 2, window_end: Date.current + 1, amount_left: 0.75)
    Items::Resolve.call(item: potato, outcome: "opened", source: "slider", start_percent: 100)

    described_class.call(item: potato.reload, percent: 100)

    expect(potato.reload).to have_attributes(opened_on: Date.current - 2, window_start: Date.current - 2,
                                             window_end: Date.current + 1, amount_left: 0.75)
  end
end
