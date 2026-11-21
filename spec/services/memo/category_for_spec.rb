require "rails_helper"

RSpec.describe Memo::CategoryFor do
  let(:household) { create(:household) }

  def category(name) = described_class.call(name: name, household: household)

  it "takes what this kitchen's own food was read as, first" do
    create(:item, household: household, display_name: "Hafermilch", canonical_name: "hafermilch",
                  category: "drinks")
    create(:product_alias, raw_text: "hafermilch", canonical_name: "Hafermilch", category: "dairy")

    expect(category("Hafermilch")).to eq("drinks")
  end

  it "then the dictionary" do
    create(:product_alias, raw_text: "gouda", canonical_name: "Gouda", category: "deli")

    expect(category("Gouda")).to eq("deli")
  end

  it "then a guess from the words, then other" do
    expect(category("Tomaten")).to eq(Categories.guess("Tomaten"))
    expect(category("Spülmittel")).to eq("other")
  end

  it "reads a line again when it is renamed" do
    line = create(:memo_item, household: household, name: "Spülmittel")
    expect(line.category).to eq("other")

    create(:product_alias, raw_text: "gouda", canonical_name: "Gouda", category: "deli")
    line.update!(name: "Gouda")

    expect(line.reload.category).to eq("deli")
  end
end
