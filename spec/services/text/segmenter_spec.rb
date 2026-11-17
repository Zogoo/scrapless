require "rails_helper"

RSpec.describe Text::Segmenter do
  def parts(text, household: nil) = described_class.call(text: text, household: household).parts

  before do
    { "bread" => "Bread", "milk" => "Milk", "eggs" => "Eggs", "butter" => "Butter",
      "brot" => "Brot", "milch" => "Milch", "eier" => "Eier", "käse" => "Käse",
      "gurken" => "Salatgurke", "olive oil" => "Olive oil", "oil" => "Oil" }.each do |raw, name|
      create(:product_alias, raw_text: raw, canonical_name: name, category: "other")
    end
  end

  # Browser recognisers return no commas (doc 15 §15.2.3); these are the
  # sentences that used to come out as one line.
  describe "a sentence with no punctuation" do
    {
      "I want to buy bread milk eggs" => %w[bread milk eggs],
      "ich brauche Brot Milch und Eier" => %w[Brot Milch Eier],
      "ich brauche brot milch und eier" => %w[brot milch eier],
      "wir brauchen noch Butter Käse und zwei Gurken" => [ "Butter", "Käse", "2 Gurken" ],
      "Ich möchte Brot, Milch und Eier kaufen" => %w[Brot Milch Eier],
      "get some milk and also bananas" => %w[milk bananas],
      "can you add a dozen eggs please" => [ "12 eggs" ]
    }.each do |said, lines|
      it "splits #{said.inspect}" do
        expect(parts(said)).to eq(lines)
      end
    end
  end

  # A memo line does not have to be a known food.
  it "keeps words it does not know as their own line" do
    expect(parts("milk toilet paper and something for Sunday")).to eq([ "milk", "toilet paper", "something for Sunday" ])
  end

  it "mixes the two languages in one list" do
    expect(parts("Milch, toilet paper, Brötchen")).to eq([ "Milch", "toilet paper", "Brötchen" ])
  end

  it "prefers the longest phrase it knows" do
    expect(parts("olive oil bread")).to eq([ "olive oil", "bread" ])
  end

  # "oat milk" and "Bio Milch" are one thing; splitting them would put
  # nonsense lines on the list.
  it "reads a short unknown run before a known word as part of it" do
    expect(parts("oat milk eggs")).to eq([ "oat milk", "eggs" ])
  end

  it "keeps an amount and its unit with the food" do
    expect(parts("2 kg Äpfel und 1.5 l milk")).to eq([ "2 kg Äpfel", "1.5 l milk" ])
  end

  it "takes a single held word as it is" do
    expect(parts("Milch")).to eq([ "Milch" ])
  end

  it "learns phrases from the kitchen's own past lines" do
    household = create(:household)
    create(:memo_item, household: household, name: "Hafer Drink")

    expect(parts("hafer drink brot", household: household)).to eq([ "hafer drink", "brot" ])
  end

  # The old splitter wrote lines like "bread milk"; learning those would glue
  # the same mistake onto every later list.
  it "does not learn a past line that is two known words run together" do
    household = create(:household)
    create(:memo_item, household: household, name: "bread milk")

    expect(parts("bread milk", household: household)).to eq(%w[bread milk])
  end

  it "reports a long sentence it could not split at all" do
    result = described_class.call(text: "something nice for the weekend party")

    expect(result.unresolved).to eq([ "something nice for the weekend party" ])
  end

  it "returns nothing for filler alone" do
    expect(parts("ich brauche noch bitte")).to eq([])
  end

  # Invariant: every word said ends up in a line or is known filler.
  it "never drops a word it does not recognise as filler" do
    said = "zwiebeln knoblauch ingwer koriander"

    expect(parts(said).join(" ").split).to eq(said.split)
  end
end
