require "rails_helper"

RSpec.describe Items::BackfillProducts do
  let(:household) { create(:household) }
  let(:egg) { Product.for("egg") }

  before do
    ProductAlias.create!(raw_text: "eier", canonical_name: "Eier", category: "dairy", product: egg, source: "seed")
  end

  it "gives food from before products existed its product, from an exact dictionary match" do
    old = create(:item, household: household, display_name: "🥚 Eier", canonical_name: "eier", category: "dairy")

    expect(described_class.call).to eq(1)
    expect(old.reload.product).to eq(egg)
  end

  # A fuzzy guess here would merge two different foods without anyone seeing it.
  it "leaves an item alone when only a near miss matches" do
    rice_pudding = create(:item, household: household, display_name: "Eierlikör", canonical_name: "eierlikör",
                                 category: "drinks")

    described_class.call

    expect(rice_pudding.reload.product).to be_nil
  end

  it "never changes a product an item already has" do
    milk = Product.for("milk")
    item = create(:item, household: household, display_name: "Eier", canonical_name: "eier", product: milk)

    described_class.call

    expect(item.reload.product).to eq(milk)
  end
end
