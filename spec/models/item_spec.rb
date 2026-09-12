require "rails_helper"

RSpec.describe Item do
  it { is_expected.to belong_to(:household) }
  it { is_expected.to validate_presence_of(:display_name) }

  it "refuses a window that ends before it starts" do
    item = build(:item, window_start: Date.current + 5, window_end: Date.current + 1)

    expect(item).not_to be_valid
    expect(item.errors[:window_end]).to be_present
  end

  # The decay bar measures the whole life, not the position inside the
  # uncertainty band — a bar that reads empty for the first 70% of a broccoli's
  # life tells the user nothing.
  describe "#life_fraction" do
    let(:item) { build(:item, acquired_on: Date.current, window_end: Date.current + 10) }

    it "is zero on the day of the shop" do
      expect(item.life_fraction).to eq(0.0)
    end

    it "reaches one at the end of the window" do
      expect(item.life_fraction(Date.current + 10)).to eq(1.0)
    end

    it "keeps counting past the end, which is what makes a ghost detectable" do
      expect(item.life_fraction(Date.current + 15)).to eq(1.5)
    end
  end
end
