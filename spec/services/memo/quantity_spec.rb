require "rails_helper"

RSpec.describe Memo::Quantity do
  {
    "2 Gurken" => [ 2, "Gurken" ],
    "2x Gurken" => [ 2, "Gurken" ],
    "2 x Gurken" => [ 2, "Gurken" ],
    "2× Gurken" => [ 2, "Gurken" ],
    "zwei Gurken" => [ 2, "Gurken" ],
    "twelve eggs" => [ 12, "eggs" ],
    "Gurken" => [ nil, "Gurken" ],
    "500 g Mehl" => [ nil, "500 g Mehl" ],    # a measure, not a count
    "1,5 l Milch" => [ nil, "1,5 l Milch" ],  # nor a fraction
    "Eier" => [ nil, "Eier" ],                # "ei…" is not "ein"
    "zwei" => [ nil, "zwei" ]                  # a number alone is a name
  }.each do |text, expected|
    it "reads #{text.inspect} as #{expected.inspect}" do
      expect(described_class.parse(text)).to eq(expected)
    end
  end

  it "caps a count at 99" do
    expect(described_class.parse("99 Brötchen").first).to eq(99)
  end
end
