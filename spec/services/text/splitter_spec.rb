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
end
