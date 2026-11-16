require "rails_helper"

RSpec.describe Copy do
  describe ".fine" do
    # Observed in QA: frozen chicken read "fine for about 270 more days".
    it "speaks of months for a freezer-length window" do
      expect(described_class.fine(270)).to eq("fine for about 9 months")
    end

    it "speaks of weeks past a fortnight" do
      expect(described_class.fine(21)).to eq("fine for about 3 weeks")
    end

    it "keeps counting days for anything short" do
      expect(described_class.fine(3)).to eq("fine for about 3 more days")
    end
  end

  describe ".bare_name" do
    it "drops an emoji that needs a variation selector, too" do
      expect(described_class.bare_name(Item.new(display_name: "🍽️ Yuzu"))).to eq("Yuzu")
    end
  end
end
