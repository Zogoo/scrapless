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

    # Observed in QA: "2 milch" came back as H-Milch, because a fuzzy hit on the
    # raw text was taken before the exact hit on the name.
    it "takes an exact match on any spelling before a fuzzy one" do
      create(:product_alias, raw_text: "h milch", canonical_name: "H-Milch", category: "dairy")
      create(:product_alias, raw_text: "milch", canonical_name: "Milch", category: "dairy")

      expect(described_class.lookup([ "2 milch", "Milch" ]).canonical_name).to eq("Milch")
    end

    # Observed in the second QA pass: "H-MILCH 3,5%" became Milk, because the
    # model's name matched exactly before the receipt line did.
    it "reads a receipt line with its quantity attached exactly, before the model's name" do
      create(:product_alias, raw_text: "h milch", canonical_name: "H-Milch", category: "dairy")
      create(:product_alias, raw_text: "milk", canonical_name: "Milk", category: "dairy")

      expect(described_class.lookup([ "H-MILCH 3,5%", "Milk" ]).canonical_name).to eq("H-Milch")
    end

    it "breaks a fuzzy tie by unexplained words, not by row order" do
      create(:product_alias, raw_text: "h milch", canonical_name: "H-Milch", category: "dairy")
      create(:product_alias, raw_text: "milch", canonical_name: "Milch", category: "dairy")

      expect(described_class.lookup("milch frisch").canonical_name).to eq("Milch")
    end

    context "with a kitchen's own corrections" do
      let(:household) { create(:household) }

      it "prefers the kitchen's correction over the shared entry" do
        create(:product_alias, household: household, raw_text: "rispentomaten",
                               canonical_name: "Cherry tomatoes", category: "produce")

        expect(described_class.lookup("RISPENTOMATEN", household: household).canonical_name)
          .to eq("Cherry tomatoes")
      end

      it "never shows one kitchen's correction to another" do
        create(:product_alias, household: household, raw_text: "yuzu kosho",
                               canonical_name: "Yuzu kosho", category: "pantry")

        expect(described_class.lookup("YUZU KOSHO", household: create(:household))).to be_nil
        expect(described_class.lookup("YUZU KOSHO")).to be_nil
      end

      # A fuzzy guess from the kitchen layer must not beat an exact shared hit.
      it "still takes an exact shared hit before a fuzzy household one" do
        create(:product_alias, household: household, raw_text: "haehnchenbrust",
                               canonical_name: "Hähnchenbrust", category: "meat_fish")

        expect(described_class.lookup("HAEHNCHENSCHENKEL", household: household).canonical_name)
          .to eq("Hähnchenschenkel")
      end
    end
  end

  describe "#display_name" do
    it "keeps the spelling it was stored with" do
      expect(build(:product_alias, canonical_name: "H-Milch").display_name).to eq("H-Milch")
      expect(build(:product_alias, canonical_name: "bread rolls").display_name).to eq("Bread rolls")
    end
  end

  describe ".record_correction!" do
    it "writes to the correcting kitchen and leaves the shared row alone" do
      household = create(:household)
      shared = described_class.find_by!(raw_text: "rispentomaten")

      described_class.record_correction!(household: household, raw_text: "RISPENTOMATEN",
                                         canonical_name: "tomatoes", category: "produce")

      expect(shared.reload.canonical_name).to eq("Rispentomaten")
      expect(household.product_aliases.find_by(raw_text: "rispentomaten").canonical_name).to eq("tomatoes")
    end

    it "does nothing without a kitchen to write to" do
      expect do
        described_class.record_correction!(household: nil, raw_text: "x y z",
                                           canonical_name: "xyz", category: "other")
      end.not_to change(described_class, :count)
    end
  end
end
