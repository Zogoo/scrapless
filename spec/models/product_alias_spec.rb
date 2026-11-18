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

  # "Hähnchenbrust" typed missed the seeded "haehnchenbrust" and cost a call.
  it "finds a word however its umlauts are spelled" do
    create(:product_alias, raw_text: "haehnchenbrust", canonical_name: "Hähnchenbrust", category: "meat_fish")

    expect(described_class.lookup("Hähnchenbrust", fuzzy: false)&.canonical_name).to eq("Hähnchenbrust")
    expect(described_class.normalize_key("Süßkartoffel")).to eq("suesskartoffel")
  end

  it "keeps letters of any script in a key" do
    expect(described_class.normalize_key("Сүү 1л")).to eq("сүү 1л")
  end

  describe "learning and sharing what kitchens agree on" do
    let(:pudding) { Product.for("rice pudding") }

    def learn_in(household, product: pudding, category: "dairy")
      described_class.learn!(household: household, raw_text: "MILCHREIS 500G", canonical_name: "milchreis",
                             category: category, product: product)
    end

    it "is shared with every kitchen once five of them agree, and not before" do
      4.times { learn_in(create(:household)) }
      expect(described_class.shared.find_by(raw_text: "milchreis")).to be_nil

      learn_in(create(:household))

      shared = described_class.shared.find_by(raw_text: "milchreis")
      expect(shared).to have_attributes(source: "promoted", votes: 5, product: pudding)
      expect(described_class.lookup("milchreis", household: create(:household), fuzzy: false)).to eq(shared)
    end

    it "shares nothing while kitchens disagree on what it is" do
      3.times { learn_in(create(:household)) }
      2.times { learn_in(create(:household), product: Product.for("rice")) }

      expect(described_class.shared.find_by(raw_text: "milchreis")).to be_nil
    end

    it "never overwrites a seeded entry" do
      seeded = create(:product_alias, raw_text: "milchreis", canonical_name: "Milchreis", category: "dairy",
                                      source: "seed", seeded: true)
      5.times { learn_in(create(:household), product: Product.for("rice"), category: "pantry") }

      expect(seeded.reload).to have_attributes(category: "dairy", source: "seed")
    end

    # Doc 7 B6: remapping a high-risk food into a low-risk category would
    # silently remove its safety carve-out for every kitchen.
    it "never makes a high-risk food low-risk for everyone" do
      shared = create(:product_alias, raw_text: "milchreis", canonical_name: "Milchreis", category: "prepared",
                                      source: "promoted")
      5.times { learn_in(create(:household), category: "pantry") }

      expect(shared.reload.category).to eq("prepared")
    end

    it "keeps a kitchen's own correction over what the model said later" do
      household = create(:household)
      described_class.record_correction!(household: household, raw_text: "milchreis", canonical_name: "Reis",
                                         category: "pantry", product: Product.for("rice"))
      learn_in(household)

      expect(described_class.find_by(household: household, raw_text: "milchreis"))
        .to have_attributes(canonical_name: "Reis", source: "correction")
    end
  end
end
