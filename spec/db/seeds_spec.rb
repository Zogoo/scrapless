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
end
