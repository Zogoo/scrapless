require "rails_helper"

RSpec.describe Captures::Ingest do
  before do
    create(:shelf_life_rule, category: "produce", storage: "fridge",
                             days_p50: 5, days_p90: 9, consume_p50: 5)
    create(:shelf_life_rule, category: "dairy", storage: "fridge",
                             days_p50: 8, days_p90: 14, consume_p50: 6)
    create(:product_alias, raw_text: "brokkoli", canonical_name: "Brokkoli",
                           category: "produce", emoji: "🥦")
  end

  let(:household) { create(:household) }
  let(:capture) { create(:capture, household: household) }

  def payload(lines)
    { "merchant" => "REWE", "purchased_on" => Date.current.iso8601, "lines" => lines }
  end

  describe "interchangeable varieties" do
    def rice_line(raw, name, product)
      { "raw_text" => raw, "name" => name, "product" => product, "row" => "food",
        "category" => "pantry", "storage" => "pantry" }
    end

    it "puts basmati and jasmine rice on one product, keeping what the model called each" do
      items = described_class.call(capture: capture, payload: payload([
        rice_line("BASMATI REIS 1KG", "Basmati-Reis", "basmati rice"),
        rice_line("JASMIN REIS", "Jasmin-Reis", "jasmine rice")
      ]))[:items]

      expect(items.map(&:product).uniq.map(&:key)).to eq([ "rice" ])
      expect(items.first.product.names).to eq("de" => "Reis")
      expect(items.map(&:source_product_key)).to eq([ "basmati rice", "jasmine rice" ])
    end

    # The seeds map "Babyspinat" to "baby spinach"; a dictionary hit has to
    # merge the same way a photo does, or it starts its own line again.
    it "merges a dictionary hit too" do
      ProductAlias.create!(raw_text: "babyspinat", canonical_name: "Babyspinat", category: "produce",
                           product: Product.create!(key: "baby spinach"), source: "seed")

      item = described_class.call(capture: capture, payload: payload([
        { "raw_text" => "BABYSPINAT", "name" => "Babyspinat", "row" => "food", "category" => "produce" }
      ]))[:items].first

      expect(item.product.key).to eq("spinach")
      expect(item.source_product_key).to eq("baby spinach")
    end

    it "keeps bread specific" do
      item = described_class.call(capture: capture, payload: payload([
        { "raw_text" => "ROGGENBROT", "name" => "Roggenbrot", "product" => "rye bread", "row" => "food",
          "category" => "bakery" }
      ]))[:items].first

      expect(item.product.key).to eq("rye bread")
    end
  end

  describe "the same food already in the kitchen" do
    let(:egg) { Product.for("egg") }
    let(:egg_line) do
      { "raw_text" => "carton of eggs", "name" => "Eier", "product" => "egg", "row" => "food",
        "category" => "dairy", "storage" => "pantry" }
    end

    before do
      create(:item, household: household, display_name: "🥚 Eier", canonical_name: "eier", category: "dairy",
                    storage: "fridge", product: egg)
    end

    # Observed: eggs in the fridge, then a photo of shopping on the worktop
    # where the model guessed "pantry", and the Kitchen showed two egg lines.
    it "puts new eggs where the eggs already are, over a guess from a photo of shopping" do
      photo = payload([ egg_line ]).merge("kind" => "food", "seen_inside" => nil)

      expect(described_class.call(capture: capture, payload: photo)[:items].first.storage).to eq("fridge")
    end

    it "believes a photo taken inside a place over the existing pack" do
      photo = payload([ egg_line ]).merge("kind" => "food", "seen_inside" => "freezer")

      expect(described_class.call(capture: capture, payload: photo)[:items].first.storage).to eq("freezer")
    end

    it "does not send fresh food to the freezer because one pack was frozen" do
      Item.update_all(storage: "freezer")

      item = described_class.call(capture: capture, payload: payload([ egg_line.merge("storage" => "fridge") ]))[:items].first

      expect(item.storage).to eq("fridge")
    end
  end

  describe "where this kitchen keeps things" do
    let(:tomato_line) do
      { "raw_text" => "TOMATEN", "name" => "Tomaten", "row" => "food", "category" => "produce", "storage" => "fridge" }
    end

    before do
      ProductAlias.create!(household: household, raw_text: "tomaten", canonical_name: "tomaten",
                           category: "produce", storage: "pantry", source: "correction")
    end

    it "puts a food where this kitchen moved it before, over the model's guess" do
      item = described_class.call(capture: capture, payload: payload([ tomato_line ]))[:items].first

      expect(item.storage).to eq("pantry")
    end

    it "believes a photo taken inside the fridge over the habit" do
      photo = payload([ tomato_line ]).merge("kind" => "food", "seen_inside" => "fridge")

      expect(described_class.call(capture: capture, payload: photo)[:items].first.storage).to eq("fridge")
    end
  end

  it "creates an item per food line, with a window on each" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "BROKKOLI", "name" => "Brokkoli", "quantity" => 1, "food" => true },
      { "raw_text" => "H-MILCH 3,5%", "name" => "Milch", "quantity" => 1, "food" => true }
    ]))

    expect(result[:items].size).to eq(2)
    expect(result[:items].map(&:window_end)).to all(be_present)
    expect(capture.reload.status).to eq("parsed")
    expect(capture.merchant).to eq("REWE")
  end

  # A food photo's labels are drawn where the model saw each item; a box that
  # is not inside the photo would draw a label in the wrong place, so it goes.
  it "returns a box per item for a food photo, and drops one that is not inside it" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "broccoli", "name" => "Brokkoli", "box" => { "x" => 0.4, "y" => 0.3, "w" => 0.8, "h" => 0.2 } },
      { "raw_text" => "milk carton", "name" => "Milch", "box" => { "x" => 1.4, "y" => 0, "w" => 0.2, "h" => 0.2 } },
      { "raw_text" => "H-MILCH", "name" => "Milch", "box" => nil }
    ]))

    expect(result[:boxes]).to eq([ { x: 0.4, y: 0.3, w: 0.6, h: 0.2 }, nil, nil ])
  end

  # Proving we filtered the deposit line is what makes the parser trustworthy,
  # so suppressed lines are returned to the review screen, not silently dropped.
  it "suppresses non-food lines and reports what it suppressed" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "BROKKOLI", "name" => "Brokkoli", "food" => true },
      { "raw_text" => "PFAND 0,25", "name" => "Pfand", "row" => "deposit" },
      { "raw_text" => "TRAGETASCHE", "name" => "Tasche", "row" => "not_food" }
    ]))

    expect(result[:items].size).to eq(1)
    expect(result[:suppressed]).to contain_exactly("PFAND 0,25", "TRAGETASCHE")
  end

  # The model's label is trusted. A word list used to overrule it and threw
  # away dumplings for containing "tasche" (bag).
  it "keeps food whose name happens to contain a non-food word" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "MAULTASCHEN", "name" => "Maultaschen", "row" => "food", "category" => "prepared" }
    ]))

    expect(result[:items].map(&:display_name)).to contain_exactly(include("Maultaschen"))
  end

  describe "a product's own shelf life" do
    before do
      allow(Ai::Config).to receive(:live?).and_return(true)
      allow(Ai::ShelfLifeReader).to receive(:call).and_return(
        "uht milk" => { "fridge" => { "typical" => 60, "max" => 90, "opened" => 4 }, "freezer" => nil, "pantry" => nil }
      )
    end

    it "gives the very first pack of a new food its own window, not its category's" do
      result = described_class.call(capture: capture, payload: payload([
        { "raw_text" => "H-MILCH 3,5%", "name" => "H-Milch", "product" => "uht milk", "row" => "food",
          "category" => "dairy", "storage" => "fridge" }
      ]))

      expect(result[:items].first.window_end).to eq(Date.current + 90)
      expect(Product.find_by(key: "uht milk").shelf_life_for("fridge")).to include(max: 90)
    end
  end

  describe "learning what the model read" do
    before do
      allow(Ai::Config).to receive(:live?).and_return(true)
      allow(Ai::ShelfLifeReader).to receive(:call).and_return({})
    end

    def model_line(raw, name, product, category: "dairy")
      { "raw_text" => raw, "name" => name, "product" => product, "row" => "food",
        "category" => category, "storage" => "fridge" }
    end

    it "keeps the model's answer for this kitchen, so the dictionary knows it next time" do
      described_class.call(capture: capture, payload: payload([ model_line("MILCHREIS 500G", "Milchreis", "rice pudding") ]))

      entry = ProductAlias.find_by(household: household, raw_text: "milchreis")
      expect(entry).to have_attributes(source: "ai", category: "dairy")
      expect(entry.product.key).to eq("rice pudding")
      expect(ProductAlias.lookup("Milchreis", household: create(:household), fuzzy: false)).to be_nil
    end

    # Observed live: the model kept Maultaschen in the cupboard, the next
    # capture's dictionary hit put them in the fridge, its category's default.
    it "remembers where the model said the food is kept" do
      line = model_line("MAULTASCHEN", "Maultaschen", "filled pasta", category: "prepared").merge("storage" => "freezer")
      described_class.call(capture: capture, payload: payload([ line ]))

      again = described_class.call(capture: create(:capture, household: household),
                                   payload: payload([ { "raw_text" => "maultaschen", "name" => "Maultaschen" } ]))

      expect(again[:items].first.storage).to eq("freezer")
    end

    it "links every item to its product, whatever it was called" do
      milk = Product.for("milk")
      create(:product_alias, raw_text: "milch", canonical_name: "Milch", category: "dairy", product: milk)

      result = described_class.call(capture: capture, payload: payload([
        model_line("MILCH", "Milch", "milk"), model_line("VOLLMILCH 1L", "Vollmilch", "milk")
      ]))

      expect(result[:items].map(&:product)).to all(eq(milk))
      expect(milk.reload.seen_names).to include("milch", "vollmilch")
    end

    it "does not learn from the offline stub, which only guesses" do
      allow(Ai::Config).to receive(:live?).and_return(false)

      described_class.call(capture: capture, payload: payload([ model_line("MILCHREIS", "Milchreis", "rice pudding") ]))

      expect(ProductAlias.where(household: household)).to be_empty
    end

    it "does not learn from a line the model did not place" do
      described_class.call(capture: capture, payload: payload([
        { "raw_text" => "XYZ 12", "name" => "Xyz", "product" => "xyz", "food" => true }
      ]))

      expect(ProductAlias.where(household: household)).to be_empty
    end
  end

  # Observed in QA: a restaurant bill put the steak and the wine in the fridge.
  it "keeps nothing from a bill for a meal eaten out, and says why" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "Filetsteak", "name" => "Filet steak", "row" => "food", "category" => "meat_fish" },
      { "raw_text" => "Merlot", "name" => "Merlot", "row" => "food", "category" => "drinks" }
    ]).merge("kind" => "bill"))

    expect(result[:items]).to be_empty
    expect(result[:suppressed]).to contain_exactly("Filetsteak", "Merlot")
    expect(result[:notes]).to eq(I18n.t("capture.bill"))
  end

  # The dictionary says what the food is; the name follows the model, which
  # writes it in the person's language.
  it "shows the model's name but takes the food's identity from the dictionary" do
    milk = Product.for("milk")
    create(:product_alias, raw_text: "frischmilch", canonical_name: "Frischmilch", category: "dairy", product: milk)

    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "FRISCHMILCH 3,5%", "name" => "fresh milk", "row" => "food", "category" => "dairy" }
    ]))

    expect(result[:items].first).to have_attributes(product: milk, category: "dairy")
    expect(result[:items].first.display_name).to include("Fresh milk")
  end

  it "uses the dictionary in preference to the model's own naming" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "BROKKOLI", "name" => "Green Vegetable Thing", "food" => true }
    ]))

    expect(result[:items].first.display_name).to include("Brokkoli")
  end

  # Never block on a partial failure: a capture that refuses to finish is a
  # capture the user stops making.
  it "keeps the lines it understood when others are unusable" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "BROKKOLI", "name" => "Brokkoli", "food" => true },
      { "raw_text" => nil, "name" => nil, "food" => true }
    ]))

    expect(result[:items].size).to eq(1)
    expect(capture.reload.status).to eq("parsed")
    expect(capture.parse_confidence).to eq(0.5)
  end

  it "marks a capture failed when nothing survived, without raising" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "PFAND 0,25", "name" => "Pfand", "row" => "deposit" }
    ]))

    expect(result[:items]).to be_empty
    expect(capture.reload.status).to eq("failed")
  end

  it "logs a captured event for every item, as training data" do
    described_class.call(capture: capture, payload: payload([
      { "raw_text" => "BROKKOLI", "name" => "Brokkoli", "food" => true }
    ]))

    expect(household.item_events.where(kind: "captured").count).to eq(1)
  end

  it "backdates the window to the day the shop happened, not the day it was uploaded" do
    result = described_class.call(capture: capture, payload: {
      "purchased_on" => (Date.current - 3).iso8601,
      "lines" => [ { "raw_text" => "BROKKOLI", "name" => "Brokkoli", "food" => true } ]
    })

    expect(result[:items].first.acquired_on).to eq(Date.current - 3)
    expect(result[:items].first.window_end).to eq(Date.current + 6)
  end

  it "does not record a printed date it never read" do
    capture = create(:capture, household: household, source: "text")
    payload = { "lines" => [ { "raw_text" => "HAEHNCHENSCHENKEL", "name" => "Chicken legs",
                               "category" => "meat_fish" } ] }

    item = described_class.call(capture: capture, payload: payload)[:items].first

    expect(item.date_label_type).to eq("none")
    expect(item.high_risk?).to be(true)
  end

  # Observed live: a till's count and weight rows came back as items named
  # "(bundle)" and "(item line repeated)", flagged food, six months each.
  it "turns only rows labelled food into items" do
    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "JOGHURT MILD", "name" => "Joghurt mild", "row" => "food", "category" => "dairy" },
      { "raw_text" => "2 Stk x 0,79", "name" => "(item line repeated)", "row" => "detail" },
      { "raw_text" => "Bundle Rabatt", "name" => "(bundle)", "row" => "discount" },
      { "raw_text" => "LEERGUT", "name" => "Leergut", "row" => "deposit" },
      { "raw_text" => "1 x Gaucho Burger", "name" => "Gaucho Burger", "row" => "not_food" }
    ]))

    expect(result[:items].map(&:display_name)).to eq([ "🥛 Joghurt mild" ])
    expect(result[:suppressed].size).to eq(4)
  end

  # A shared four-letter prefix once made "HAEHN.BRUSTFILET" chicken thighs.
  it "keeps the model's name and category over a fuzzy dictionary guess" do
    create(:product_alias, raw_text: "haehnchenschenkel", canonical_name: "Hähnchenschenkel", category: "meat_fish")

    result = described_class.call(capture: capture, payload: payload([
      { "raw_text" => "HAEHN.BRUSTFILET", "name" => "Hähnchenbrustfilet", "row" => "food",
        "category" => "meat_fish", "storage" => "fridge" }
    ]))

    expect(result[:items].first).to have_attributes(display_name: "🍗 Hähnchenbrustfilet", category: "meat_fish")
  end

  it "still lets a fuzzy match fill in a line nobody categorised" do
    create(:product_alias, raw_text: "haehnchenschenkel", canonical_name: "Hähnchenschenkel", category: "meat_fish")

    result = described_class.call(capture: capture, payload: payload([ { "raw_text" => "HAEHNCH.SCHENK." } ]))

    expect(result[:items].first.display_name).to end_with("Hähnchenschenkel")
  end
end
