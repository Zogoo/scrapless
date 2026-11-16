require "rails_helper"

RSpec.describe Notifications::Message do
  let(:household) { create(:household) }
  let(:spinach) { create(:item, household: household, display_name: "🥬 Spinat") }
  let(:broccoli) { create(:item, household: household, display_name: "Brokkoli") }

  def message(items, locale: "en")
    notification = create(:notification, household: household, item_ids: items.map(&:id))
    described_class.call(notification: notification, locale: locale)
  end

  it "names the food plainly, in the order it was ranked, and opens Today" do
    payload = message([ spinach, broccoli ])

    expect(payload[:body]).to eq("Spinat and Brokkoli want using tonight.")
    expect(payload[:url]).to match(%r{\A/today\?n=\d+\z})
    expect(payload[:tag]).to eq(described_class::TAG)
  end

  it "speaks the phone's language" do
    expect(message([ spinach ], locale: "de")[:body]).to eq("Spinat am besten heute Abend verbrauchen.")
  end

  it "leaves out food that was used up since" do
    broccoli.update!(state: "rescued", resolved_at: Time.current)

    expect(message([ spinach, broccoli ])[:body]).to eq("Spinat wants using tonight.")
  end

  it "sends nothing when all of it is gone" do
    spinach.update!(state: "rescued", resolved_at: Time.current)

    expect(message([ spinach ])).to be_nil
  end

  # Never "use it tonight" for food where that could be unsafe (doc 4 §4.13).
  it "only suggests checking high-risk food" do
    chicken = create(:item, household: household, display_name: "Hähnchen", category: "meat_fish")

    expect(message([ chicken ])[:body]).to eq("Hähnchen — worth a look tonight.")
  end
end
