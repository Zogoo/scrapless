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

  describe "#shelf_life_for" do
    it "reads one place as whole days" do
      product = described_class.create!(key: "milk", shelf_life: {
        "fridge" => { "typical" => 6, "max" => 9, "opened" => 4 }, "pantry" => nil
      })

      expect(product.shelf_life_for("fridge")).to eq(typical: 6, max: 9, opened: 4)
      expect(product.shelf_life_for("pantry")).to be_nil
      expect(product.shelf_life_for("freezer")).to be_nil
    end

    # A bad row must degrade to the category rule, never to a wrong window.
    it "ignores an answer that cannot be right" do
      product = described_class.create!(key: "odd", shelf_life: {
        "fridge" => { "typical" => 20, "max" => 5, "opened" => nil },
        "freezer" => { "typical" => 0, "max" => 90, "opened" => nil },
        "pantry" => { "typical" => 30, "max" => 99_999, "opened" => nil }
      })

      expect(described_class::PLACES.map { |place| product.shelf_life_for(place) }).to all(be_nil)
      expect(product).not_to be_shelf_life_known
    end
  end
end
