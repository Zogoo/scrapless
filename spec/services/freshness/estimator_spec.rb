require "rails_helper"

RSpec.describe Freshness::Estimator do
  before do
    create(:shelf_life_rule, category: "produce", storage: "fridge",
                             days_p50: 5, days_p90: 9, consume_p50: 5)
    create(:shelf_life_rule, category: "produce", storage: "freezer",
                             days_p50: 180, days_p90: 300, consume_p50: 90)
    create(:shelf_life_rule, category: "meat_fish", storage: "fridge",
                             days_p50: 2, days_p90: 3, consume_p50: 2, high_risk: true)
  end

  it "opens the band part-way through the median shelf life, not on day one" do
    result = described_class.call(category: "produce", acquired_on: Date.current)

    expect(result.window_start).to eq(Date.current + 4)
    expect(result.window_end).to eq(Date.current + 9)
    expect(result.confidence).to eq(0.6)
  end

  it "falls back with low confidence for a category it has no rule for" do
    result = described_class.call(category: "nonsense", acquired_on: Date.current)

    expect(result.confidence).to eq(0.3)
    expect(result.window_end).to eq(Date.current + 10)
  end

  # The bug this guards: treating the freezer as a multiplier on a fridge window
  # gives frozen chicken a life of days instead of months.
  it "looks the freezer up rather than scaling the fridge window" do
    fridge = described_class.call(category: "produce", storage: "fridge")
    freezer = described_class.call(category: "produce", storage: "freezer")

    expect(freezer.window_end - fridge.window_end).to be > 200
  end

  context "with a printed date" do
    it "never extends a Verbrauchsdatum, because it is a safety date" do
      printed = Date.current + 2
      result = described_class.call(category: "meat_fish", acquired_on: Date.current,
                                    date_label_type: "verbrauchsdatum", date_label_value: printed)

      expect(result.window_end).to eq(printed)
      expect(result.high_risk).to be(true)
      expect(result.confidence).to eq(0.95)
    end

    it "allows a Mindesthaltbarkeitsdatum to extend, because it is a quality date" do
      printed = Date.current + 2
      result = described_class.call(category: "produce", acquired_on: Date.current,
                                    date_label_type: "mhd", date_label_value: printed)

      expect(result.window_end).to eq(printed + 3)
      expect(result.high_risk).to be(false)
    end
  end

  it "shortens the window from the day it was opened" do
    result = described_class.call(category: "produce", acquired_on: Date.current - 5,
                                  opened_on: Date.current)

    expect(result.window_end).to eq(Date.current + 3)
  end

  it "never returns a window that ends before it starts" do
    result = described_class.call(category: "meat_fish", acquired_on: Date.current,
                                  date_label_type: "verbrauchsdatum",
                                  date_label_value: Date.current - 5)

    expect(result.window_end).to be >= result.window_start
    expect(result.window_start).to be >= Date.current
  end
end
