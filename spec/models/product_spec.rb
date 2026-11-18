require "rails_helper"

RSpec.describe Product do
  it "is one row per key, however the model spelled it" do
    expect(described_class.for("UHT  Milk")).to eq(described_class.for("uht milk"))
    expect(described_class.count).to eq(1)
  end

  it "is nothing for a blank key, so a line without one stays unlinked" do
    expect(described_class.for(" ")).to be_nil
  end

  it "knows every name it was seen under, in any language" do
    milk = described_class.for("milk")
    create(:product_alias, raw_text: "milch", canonical_name: "Milch", category: "dairy", product: milk)
    create(:product_alias, raw_text: "milk", canonical_name: "Milk", category: "dairy", product: milk)

    expect(milk.names).to include("Milch", "Milk", "milch", "milk")
  end
end
