require "rails_helper"

RSpec.describe Items::Undo do
  let(:household) { create(:household) }
  let(:item) { create(:item, household: household, amount_left: 1.0) }

  it "puts a food back exactly as it was before the tap" do
    window = [ item.window_start, item.window_end ]
    Items::Resolve.call(item: item, outcome: "froze")

    described_class.call(item: item)

    expect(item.reload).to have_attributes(state: "active", storage: "fridge", storage_changed_at: nil)
    expect([ item.window_start, item.window_end ]).to eq(window)
  end

  it "brings a food marked gone back to the list" do
    Items::Resolve.call(item: item, outcome: "wasted")

    described_class.call(item: item)

    expect(item.reload.state).to eq("active")
    expect(item.item_events.where(kind: "wasted")).to be_empty
  end

  # The presence model counts partial_use events, so undo must remove the event.
  it "takes a half-use out of the presence model too" do
    Items::Resolve.call(item: item, outcome: "partial")

    described_class.call(item: item)

    expect(item.reload.amount_left).to eq(1.0)
    expect(item.item_events.where(kind: "partial_use")).to be_empty
  end

  it "only undoes a tap made just now" do
    Items::Resolve.call(item: item, outcome: "used")
    item.item_events.last.update!(at: 11.minutes.ago)

    expect { described_class.call(item: item) }.to raise_error(described_class::NotUndoable)
  end

  it "does not undo something that was not a tap" do
    item.item_events.create!(household: household, kind: "captured", meta: {}.to_json)

    expect { described_class.call(item: item) }.to raise_error(described_class::NotUndoable)
  end
end
