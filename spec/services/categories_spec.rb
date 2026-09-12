require "rails_helper"

RSpec.describe Categories do
  describe ".guess" do
    it "reads German compounds, which is most of a German receipt" do
      expect(described_class.guess("Vollkornbrot")).to eq("bakery")
      expect(described_class.guess("Hähnchenschenkel")).to eq("meat_fish")
      expect(described_class.guess("Frischmilch")).to eq("dairy")
    end

    # Observed live: bread rolls were filed as dairy, because the dairy keyword
    # "ei" is a substring of "weizenbrötchen" — which handed bread a 14-day
    # fridge window instead of a 5-day pantry one.
    it "does not let a two-letter keyword match inside a longer word" do
      expect(described_class.guess("WEIZENBROETCHEN 6ER")).to eq("bakery")
      expect(described_class.guess("Weizenbrötchen")).to eq("bakery")
    end

    it "still finds the short keyword when it stands alone" do
      expect(described_class.guess("Bio Eier 10St")).to eq("dairy")
    end

    it "says other rather than guessing" do
      expect(described_class.guess("Yuzu Kosho")).to eq("other")
    end
  end
end
