require "rails_helper"

RSpec.describe Ai::ShelfLifeReader do
  let(:router) { instance_double(Ai::Router) }

  before { allow(Ai::Router).to receive(:new).and_return(router) }

  it "asks once for all the new products, on the shelf_life tier" do
    allow(router).to receive(:json_completion).and_return("products" => [])

    described_class.call(products: [ "milk", "jam", "milk" ])

    expect(router).to have_received(:json_completion) do |purpose:, messages:, **|
      expect(purpose).to eq(:shelf_life)
      expect(JSON.parse(messages.last[:content])).to eq([ "milk", "jam" ])
      expect(messages.first[:content]).to include("most perishable common kind")
    end
  end

  it "returns each asked product's places and drops anything it was not asked about" do
    allow(router).to receive(:json_completion).and_return("products" => [
      { "product" => "milk", "fridge" => { "typical" => 6, "max" => 9, "opened" => 4 }, "freezer" => nil, "pantry" => nil },
      { "product" => "caviar", "fridge" => { "typical" => 30, "max" => 60, "opened" => 2 }, "freezer" => nil, "pantry" => nil }
    ])

    result = described_class.call(products: [ "milk" ])

    expect(result.keys).to eq([ "milk" ])
    expect(result["milk"]["fridge"]).to include("max" => 9)
  end

  it "does not call the model for nothing" do
    allow(router).to receive(:json_completion)

    expect(described_class.call(products: [])).to eq({})
    expect(router).not_to have_received(:json_completion)
  end
end
