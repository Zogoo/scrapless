require "rails_helper"

RSpec.describe Products::LearnShelfLife do
  let(:milk) { Product.create!(key: "milk") }
  let(:jam) { Product.create!(key: "jam", shelf_life: { "pantry" => { "typical" => 300, "max" => 700, "opened" => nil } }) }
  let(:answer) do
    { "milk" => { "fridge" => { "typical" => 6, "max" => 9, "opened" => 4 }, "freezer" => nil, "pantry" => nil } }
  end

  before { allow(Ai::ShelfLifeReader).to receive(:call).and_return(answer) }

  it "asks nothing without a live model, so the stub never teaches a shelf life" do
    described_class.call(products: [ milk ])

    expect(Ai::ShelfLifeReader).not_to have_received(:call)
    expect(milk.reload.shelf_life).to be_nil
  end

  context "when live" do
    before { allow(Ai::Config).to receive(:live?).and_return(true) }

    it "asks only about products nobody has asked about, and keeps the answer for every kitchen" do
      described_class.call(products: [ milk, jam ])

      expect(Ai::ShelfLifeReader).to have_received(:call).with(products: [ "milk" ], household: nil)
      expect(milk.reload.shelf_life_for("fridge")).to eq(typical: 6, max: 9, opened: 4)
      expect(milk.shelf_life_for("pantry")).to be_nil
    end

    it "keeps the first answer" do
      milk.update!(shelf_life: { "fridge" => { "typical" => 5, "max" => 7, "opened" => 3 } })

      described_class.call(products: [ milk ])

      expect(Ai::ShelfLifeReader).not_to have_received(:call)
      expect(milk.reload.shelf_life_for("fridge")[:max]).to eq(7)
    end

    it "stores nothing when no place in the answer is usable" do
      allow(Ai::ShelfLifeReader).to receive(:call)
        .and_return("milk" => { "fridge" => { "typical" => 9, "max" => 2, "opened" => nil } })

      described_class.call(products: [ milk ])

      expect(milk.reload.shelf_life).to be_nil
    end

    # A capture must never fail because the shelf-life question did.
    it "carries on when the model is unavailable" do
      allow(Ai::ShelfLifeReader).to receive(:call).and_raise(Ai::Client::TimedOut, "slow")

      expect(described_class.call(products: [ milk ])).to eq([])
      expect(milk.reload.shelf_life).to be_nil
    end
  end
end
