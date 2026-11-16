require "rails_helper"

RSpec.describe Notifications::Dispatch do
  include ActiveJob::TestHelper

  let(:household) { create(:household, timezone: "Europe/Berlin") }
  # Wednesday 18 November 2026, 18:30 in Berlin.
  let(:dinner) { Time.utc(2026, 11, 18, 17, 30) }

  around { |example| with_env(vapid_env) { example.run } }

  before do
    travel_to dinner
    create(:shelf_life_rule, category: "produce", storage: "fridge", days_p50: 5, days_p90: 9, consume_p50: 5)
    create(:item, :at_risk, household: household)
    create_list(:push_subscription, 2, household: household)
  end

  def dispatch(at = dinner) = described_class.call(at: at)

  it "spends one slot and sends to every phone in the kitchen" do
    expect { dispatch }.to change(household.notifications, :count).by(1)
      .and have_enqueued_job(Notifications::DeliverPushJob).exactly(2).times

    expect(household.notifications.last).to have_attributes(slot: 1, iso_week: "2026-W47",
                                                            sent_on: Date.new(2026, 11, 18))
  end

  # The clock is an hourly tick that may repeat or arrive late.
  it "sends nothing on a second tick the same evening" do
    dispatch

    expect { dispatch(dinner + 1.hour) }.not_to have_enqueued_job(Notifications::DeliverPushJob)
  end

  it "waits for the kitchen's dinner time, in its own time zone" do
    expect(dispatch(Time.utc(2026, 11, 18, 12))).to be_empty
    expect(dispatch(Time.utc(2026, 11, 18, 19))).to be_empty # 20:00 in Berlin
  end

  it "keeps to the weekly budget" do
    create(:notification, household: household, sent_on: Date.new(2026, 11, 16))

    expect(dispatch).to be_empty
  end

  it "spends a second slot when the kitchen allows two a week" do
    household.update!(alerts_per_week: 2)
    create(:notification, household: household, sent_on: Date.new(2026, 11, 16))

    expect(dispatch.first.slot).to eq(2)
  end

  it "stays silent, and keeps its budget, when nothing is worth saying" do
    household.items.destroy_all

    expect { dispatch }.not_to change(Notification, :count)
  end

  it "does nothing for a kitchen that turned notifications off" do
    household.update!(alerts_per_week: 0)

    expect(dispatch).to be_empty
  end

  it "does nothing without push keys" do
    with_env("VAPID_PRIVATE_KEY" => nil) { expect(dispatch).to be_empty }
  end
end
