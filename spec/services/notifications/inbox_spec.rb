require "rails_helper"

RSpec.describe Notifications::Inbox do
  let(:household) { create(:household, timezone: "Europe/Berlin") }
  let(:spinach) { create(:item, household: household, display_name: "Spinat") }
  let(:milk) { create(:item, household: household, display_name: "Milch") }

  before { travel_to Time.utc(2026, 11, 18, 17, 30) }

  def inbox(locale: "en") = described_class.call(household: household, locale: locale)

  it "lists the last two weeks, newest first, with the words that were sent" do
    create(:notification, household: household, item_ids: [ spinach.id ], sent_on: Date.new(2026, 11, 11))
    newest = create(:notification, household: household, item_ids: [ milk.id ], sent_on: Date.new(2026, 11, 18))
    create(:notification, household: household, item_ids: [ milk.id ], sent_on: Date.new(2026, 11, 4))

    expect(inbox.map { |entry| entry[:body] }).to eq([ "Milch wants using tonight.", "Spinat wants using tonight." ])
    expect(inbox.first).to include(id: newest.id, url: "/today?n=#{newest.id}", read: false, unread: true)
  end

  it "speaks the phone's language" do
    create(:notification, household: household, item_ids: [ spinach.id ])

    expect(inbox(locale: "de").first[:body]).to eq("Spinat am besten heute Abend verbrauchen.")
  end

  it "stops counting one once someone in the kitchen has read it" do
    create(:notification, household: household, item_ids: [ spinach.id ], opened_at: Time.current)

    expect(inbox.first).to include(read: true, unread: false)
  end

  # The badge points at food to use, never at food already gone.
  it "stops counting one once all its food is used, but still shows it" do
    create(:notification, household: household, item_ids: [ spinach.id ])
    spinach.update!(state: "rescued", resolved_at: Time.current)

    expect(inbox.first).to include(body: "Spinat wants using tonight.", live: false, unread: false)
    expect(described_class.unread(household: household)).to eq(0)
  end

  it "leaves out one whose food has all been deleted" do
    create(:notification, household: household, item_ids: [ spinach.id ])
    spinach.destroy!

    expect(inbox).to be_empty
  end

  it "shows only this kitchen's" do
    create(:notification, item_ids: [ create(:item).id ])

    expect(inbox).to be_empty
  end
end
