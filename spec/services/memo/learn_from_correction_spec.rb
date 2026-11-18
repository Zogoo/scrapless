require "rails_helper"

RSpec.describe Memo::LearnFromCorrection do
  let(:household) { create(:household) }

  before do
    create(:product_alias, raw_text: "milch", canonical_name: "Milch", category: "dairy")
    Text::Lexicon.reset!
  end

  def correct(from, to, source: "voice")
    item = create(:memo_item, household: household, name: from, source: source)
    item.update!(name: to)
    described_class.call(item: item, previous_name: from)
  end

  def learned(kind) = household.vocabulary_entries.where(kind: kind).pluck(:phrase)

  it "learns the words cut off either end as this kitchen's filler" do
    correct("Ich hätt gern Milch bitte schön", "Milch")

    expect(learned("leading")).to eq([ "ich hätt gern" ])
    expect(learned("trailing")).to eq([ "bitte schön" ])
  end

  it "learns the corrected name as an item phrase" do
    correct("Hafer", "Hafer Milch")

    expect(learned("item")).to eq([ "hafer milch" ])
  end

  # Two items glued together: the cut-off word is food, not filler.
  it "does not learn a known item as filler" do
    correct("tortillas milch", "tortillas")

    expect(learned("trailing")).to be_empty
  end

  it "learns nothing from a line a person typed" do
    correct("Milch", "Hafer Milch", source: "text")

    expect(household.vocabulary_entries).to be_empty
  end

  it "learns no filler from a rewrite that is not a trim" do
    correct("Brot", "Brötchen")

    expect(learned("leading") + learned("trailing")).to be_empty
  end
end
