require "rails_helper"

RSpec.describe Products::RecomputeMerges do
  let(:household) { create(:household) }
  let(:io) { StringIO.new }
  let(:shelf) { { "pantry" => { "typical" => 365, "max" => 730, "opened" => 180 } } }

  # As they were before merging existed: one product per variety, no source key.
  let!(:basmati) do
    product = Product.create!(key: "basmati rice", shelf_life: shelf)
    create_list(:item, 2, household: household, display_name: "Basmati-Reis", canonical_name: "basmati-reis",
                          category: "pantry", storage: "pantry", raw_text: "BASMATI REIS", product: product)
    ProductAlias.create!(household: household, raw_text: "basmati reis", canonical_name: "Basmati-Reis",
                         category: "pantry", product: product, source: "ai")
    product
  end
  let!(:jasmine) do
    product = Product.create!(key: "jasmine rice")
    create(:item, household: household, display_name: "Jasmin-Reis", canonical_name: "jasmin-reis",
                  category: "pantry", storage: "pantry", raw_text: "JASMIN REIS", product: product)
    product
  end

  def run(dry_run:, rules: Products::MergeKey.rules) = described_class.call(dry_run: dry_run, rules: rules, io: io)

  it "writes nothing on a dry run and says what it would do" do
    run(dry_run: true)

    expect(io.string).to include("basmati rice (2 items) -> rice", "jasmine rice (1 items) -> rice")
    expect(Product.find_by(key: "rice")).to be_nil
    expect(Item.pluck(:source_product_key).compact).to be_empty
  end

  it "merges varieties onto one product, keeping their original keys and shelf life" do
    run(dry_run: false)

    rice = Product.find_by!(key: "rice")
    expect(rice.items.count).to eq(3)
    expect(rice.names).to eq("de" => "Reis")
    expect(rice.shelf_life).to eq(shelf)
    expect(Item.pluck(:source_product_key)).to contain_exactly("basmati rice", "basmati rice", "jasmine rice")
    expect(ProductAlias.find_by(raw_text: "basmati reis").product).to eq(rice)
    expect(Product.where(key: [ "basmati rice", "jasmine rice" ])).to be_empty
  end

  it "changes nothing on a second run" do
    run(dry_run: false)
    snapshot = Item.order(:id).pluck(:product_id, :source_product_key)

    expect(run(dry_run: false)).to eq(items: [], aliases: [])
    expect(Item.order(:id).pluck(:product_id, :source_product_key)).to eq(snapshot)
  end

  it "splits the varieties back apart when rice leaves the merge list" do
    run(dry_run: false)
    config = YAML.safe_load_file(Products::MergeKey::CONFIG_PATH)
    config["merge_heads"].delete("rice")
    without_rice = Products::MergeKey.load_rules(config)

    run(dry_run: false, rules: without_rice)

    expect(Product.find_by!(key: "basmati rice").items.count).to eq(2)
    expect(Product.find_by!(key: "jasmine rice").items.count).to eq(1)
    expect(ProductAlias.find_by(raw_text: "basmati reis").product.key).to eq("basmati rice")
    expect(run(dry_run: false, rules: without_rice)).to eq(items: [], aliases: [])
  end
end
