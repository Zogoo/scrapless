require "rails_helper"

RSpec.describe Memo::BackfillCategories do
  let(:household) { create(:household) }
  let!(:line) { create(:memo_item, household: household, name: "Gouda") }

  before do
    create(:product_alias, raw_text: "gouda", canonical_name: "Gouda", category: "deli")
    line.update_columns(category: "other") # as written before sections existed
  end

  it "reports and writes nothing on a dry run" do
    io = StringIO.new
    described_class.call(dry_run: true, io: io)

    expect(io.string).to include("1 lines -> deli")
    expect(line.reload.category).to eq("other")
  end

  it "gives each line its section" do
    described_class.call(dry_run: false, io: StringIO.new)

    expect(line.reload.category).to eq("deli")
  end
end
