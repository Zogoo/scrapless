require "rails_helper"

RSpec.describe Products::MergeKey do
  {
    [ "basmati rice", "pantry" ] => "rice",
    [ "jasmine rice", "pantry" ] => "rice",
    [ "rice flour", "pantry" ] => "flour",
    [ "brown sugar", "pantry" ] => "sugar",
    [ "rolled oat", "pantry" ] => "oat",
    [ "green tea", "pantry" ] => "tea",
    [ "white grape", "produce" ] => "grape",
    [ "red onion", "produce" ] => "onion",
    [ "baby spinach", "produce" ] => "spinach",
    [ "red cabbage", "produce" ] => "cabbage",
    [ "cherry tomato", "produce" ] => "tomato",
    [ "sour cherry", "produce" ] => "cherry",
    [ "honeydew melon", "produce" ] => "melon",
    [ "red bell pepper", "produce" ] => "bell pepper",
    [ "sparkling mineral water", "drinks" ] => "mineral water",
    [ "wheat beer", "drinks" ] => "beer",
    [ "pineapple", "produce" ] => "pineapple",           # whole words
    [ "watermelon", "produce" ] => "watermelon",         # own head
    [ "sweet potato", "produce" ] => "sweet potato",     # exception
    [ "white radish", "produce" ] => "white radish",     # exception
    [ "icing sugar", "pantry" ] => "icing sugar",        # exception
    [ "iced tea", "drinks" ] => "iced tea",              # exception
    [ "canned tomato", "pantry" ] => "canned tomato",    # processing word
    [ "tomato sauce", "pantry" ] => "tomato sauce",      # processing word
    [ "apple juice", "drinks" ] => "apple juice",        # processing word
    [ "black pepper", "pantry" ] => "black pepper",      # no head
    [ "rye bread", "bakery" ] => "rye bread",            # category
    [ "uht milk", "dairy" ] => "uht milk"                # category
  }.each do |(key, category), expected|
    it "#{key} (#{category}) -> #{expected}" do
      expect(described_class.call(key: key, category: category)).to eq(expected)
    end
  end

  it "normalizes the key it is given" do
    expect(described_class.call(key: "Basmati-Rice", category: "pantry")).to eq("rice")
  end

  it "names a head in German only" do
    expect(described_class.name_for("rice", :de)).to eq("Reis")
    expect(described_class.name_for("rice", :en)).to be_nil
  end

  describe "config/product_merge.yml" do
    let(:rules) { described_class.rules }

    it "gives every head a German title" do
      expect(rules.heads).to all(satisfy { |_head, title| title.present? })
    end

    it "lists no exception that is itself a head" do
      expect(rules.exceptions & rules.heads.keys.to_set).to be_empty
    end
  end
end
