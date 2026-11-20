require "rails_helper"

RSpec.describe Text::Splitter do
  before do
    create(:product_alias, raw_text: "milch", canonical_name: "Milch", category: "dairy")
    create(:product_alias, raw_text: "brokkoli", canonical_name: "Brokkoli", category: "produce")
  end

  # Every line resolved here is a line that never reaches a paid model, which is
  # the mechanism the whole cost model depends on.
  it "resolves known words for free and sends only the rest onward" do
    known, unknown = described_class.call(text: "milch, brokkoli and yuzu kosho")

    expect(known.map { |k| k["name"] }).to contain_exactly("Milch", "Brokkoli")
    expect(unknown).to eq([ "yuzu kosho" ])
  end

  # A near-miss is not knowledge: "milchreis" is not Milch. It goes to the
  # model, which says what it is, and that answer is kept for next time.
  it "counts only an exact match as known" do
    known, unknown = described_class.call(text: "milchreis, milch")

    expect(known.map { |k| k["name"] }).to eq([ "Milch" ])
    expect(unknown).to eq([ "milchreis" ])
  end

  # A word this kitchen taught it is free here, and only here.
  it "uses the kitchen's own corrections, and no one else's" do
    household = create(:household)
    create(:product_alias, household: household, raw_text: "yuzu kosho", canonical_name: "Yuzu kosho",
                           category: "pantry")

    _, unknown_here = described_class.call(text: "yuzu kosho", household: household)
    _, unknown_elsewhere = described_class.call(text: "yuzu kosho", household: create(:household))

    expect(unknown_here).to be_empty
    expect(unknown_elsewhere).to eq([ "yuzu kosho" ])
  end

  it "pulls the quantity off the front of a line" do
    known, = described_class.call(text: "2 milch")

    expect(known.first["quantity"]).to eq(2.0)
  end

  it "understands the separators people actually speak" do
    known, = described_class.call(text: "milch und brokkoli")

    expect(known.size).to eq(2)
  end

  it "returns nothing rather than guessing at an empty input" do
    expect(described_class.call(text: "  ")).to eq([ [], [] ])
  end

  describe "unknown words before a known one" do
    before { create(:product_alias, raw_text: "reis", canonical_name: "Reis", category: "pantry") }

    # One line for the model, not "Reis" plus a separate "Basmati".
    it "sends the whole line to the model while the dictionary does not know it" do
      known, unknown = described_class.call(text: "basmati reis")

      expect(known).to be_empty
      expect(unknown).to eq([ "basmati reis" ])
    end

    it "is free once the dictionary knows it" do
      create(:product_alias, raw_text: "basmati reis", canonical_name: "Basmati-Reis", category: "pantry")

      known, unknown = described_class.call(text: "basmati reis")

      expect(known.map { |k| k["name"] }).to eq([ "Basmati-Reis" ])
      expect(unknown).to be_empty
    end
  end
end
