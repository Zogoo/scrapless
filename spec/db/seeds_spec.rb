require "rails_helper"

# The tap grid (frontend capture.ts) sends fixed words. Each must resolve from
# the seeded dictionary, or a tap — the cheapest capture there is — silently
# becomes a paid model call, or a second Kitchen line for the same food.
RSpec.describe "db/seeds.rb" do
  grid = Rails.root.join("frontend/src/app/features/capture/capture.ts").read.scan(/word: '([^']+)'/).flatten

  before { Rails.application.load_seed }

  it "finds the twenty tap-grid words" do
    expect(grid.size).to eq(20)
  end

  it "resolves every tap-grid word for free, to itself" do
    unresolved = grid.reject { |word| ProductAlias.lookup(word)&.canonical_name == word }

    expect(unresolved).to be_empty
  end

  # Doc 3: food we cannot place gets a wide "about a week?" band — never the
  # half year a cupboard used to give it.
  it "gives food nobody could place about a week, in the cupboard too" do
    %w[fridge pantry].each do |storage|
      window = Freshness::Estimator.call(category: "other", storage: storage, acquired_on: Date.current)
      expect(window.window_end - Date.current).to be <= 14
    end
  end

  # Tins are pantry; meat or fish in the cupboard is raw food left out.
  it "never keeps meat or fish in the cupboard for more than a day" do
    window = Freshness::Estimator.call(category: "meat_fish", storage: "pantry", acquired_on: Date.current)

    expect(window.window_end - Date.current).to be <= 1
  end

  # Without a product a seeded word cannot be grouped with its other names.
  it "gives every seeded word a product" do
    expect(ProductAlias.shared.where(product_id: nil)).to be_empty
    expect(ProductAlias.shared.find_by(raw_text: "milch").product).to eq(ProductAlias.shared.find_by(raw_text: "milk").product)
  end
end
