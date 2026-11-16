require "rails_helper"

RSpec.describe Notification do
  let(:household) { create(:household) }

  before { travel_to Time.utc(2026, 11, 18, 12) } # a Wednesday: tomorrow is the same week

  it "uses the ISO week-year, so New Year's Eve can be week 53 or week 1" do
    expect(described_class.week_of(Date.new(2026, 12, 31))).to eq("2026-W53")
    expect(described_class.week_of(Date.new(2024, 12, 30))).to eq("2025-W01")
  end

  # The weekly cap is an invariant (doc 5 §5.5), so the database holds it.
  it "cannot spend the same slot twice" do
    create(:notification, household: household, sent_on: Date.current)

    expect { create(:notification, household: household, sent_on: Date.current + 1) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "cannot send twice on the same day" do
    create(:notification, household: household)

    expect { create(:notification, household: household, slot: 2) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "has at most three slots a week" do
    expect(build(:notification, household: household, slot: 4)).not_to be_valid
  end
end
