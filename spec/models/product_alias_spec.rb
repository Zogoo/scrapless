require "rails_helper"

RSpec.describe ProductAlias do
  before do
    create(:product_alias, raw_text: "rispentomaten", canonical_name: "Rispentomaten", category: "produce")
    create(:product_alias, raw_text: "haehnchenschenkel", canonical_name: "Hähnchenschenkel",
                           category: "meat_fish")
    create(:product_alias, raw_text: "gurk sal stck", canonical_name: "Salatgurke", category: "produce")
  end

  describe ".lookup" do
    it "matches a line exactly as printed" do
      expect(described_class.lookup("RISPENTOMATEN")&.canonical_name).to eq("Rispentomaten")
    end

    # Doc 4 §4.4's own worked example of an unreadable line.
    it "resolves the house abbreviation for a cucumber" do
      expect(described_class.lookup("GURK.SAL.STCK")&.canonical_name).to eq("Salatgurke")
    end

    # Observed live: the till printed "RISPENTOMAT." and the lookup missed, so a
    # tomato was filed as "other" and given a 180-day pantry window.
    it "matches a line the till truncated" do
      expect(described_class.lookup("RISPENTOMAT.")&.canonical_name).to eq("Rispentomaten")
      expect(described_class.lookup("HAEHNCH.SCHENK.")&.canonical_name).to eq("Hähnchenschenkel")
    end

    it "still returns nothing for a word it has never seen" do
      expect(described_class.lookup("YUZU KOSHO")).to be_nil
    end

    # A two-letter overlap would match almost anything.
    it "does not match on a fragment too short to mean anything" do
      expect(described_class.lookup("RI")).to be_nil
    end
  end
end
