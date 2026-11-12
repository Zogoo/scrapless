require "rails_helper"

RSpec.describe Recipes::GroundInInventory do
  let(:household) { create(:household) }
  let!(:broccoli) { create(:item, household: household, display_name: "🥦 Brokkoli", canonical_name: "brokkoli") }
  let!(:milk) { create(:item, household: household, display_name: "🥛 Milch", canonical_name: "milch", category: "dairy") }
  let!(:rolls) do
    create(:item, household: household, display_name: "🥖 Weizenbrötchen", canonical_name: "weizenbrötchen",
                  category: "bakery", storage: "pantry")
  end
  let(:items) { [ broccoli, milk, rolls ] }

  def ingredient(name, item_id: nil, optional: false, amount: nil)
    { "item_id" => item_id, "name" => name, "amount" => amount, "optional" => optional }
  end

  def ground(ingredients, steps: [ "Cook the Brokkoli in the Milch." ], use_first_ids: [], title: "Brokkoli bake")
    described_class.call(recipe: { "title" => title, "minutes" => 20, "ingredients" => ingredients, "steps" => steps },
                         items: items, use_first_ids: use_first_ids)
  end

  def bound_ids(recipe) = recipe[:ingredients].map { |i| i[:item_id] }

  it "binds an ingredient to the item the model named by id, using the item's own name" do
    recipe = ground([ ingredient("broccoli florets", item_id: broccoli.id) ])

    expect(recipe[:ingredients].first).to include(item_id: broccoli.id, name: "Brokkoli")
  end

  it "falls back to the name when the id is missing or not in this kitchen" do
    recipe = ground([ ingredient("Milch", item_id: 999_999) ])

    expect(bound_ids(recipe)).to eq([ milk.id ])
  end

  # Receipt jargon the dictionary has already learned should bind the same way
  # it resolves on a capture.
  it "uses the receipt dictionary to recognise a name it has seen before" do
    create(:product_alias, raw_text: "vollmilch", canonical_name: "milch", category: "dairy")

    recipe = ground([ ingredient("Vollmilch") ], steps: [ "Warm the Vollmilch." ])

    expect(bound_ids(recipe)).to eq([ milk.id ])
  end

  it "uses each item at most once" do
    recipe = ground([ ingredient("Brokkoli", item_id: broccoli.id), ingredient("more Brokkoli", item_id: broccoli.id) ])

    expect(bound_ids(recipe)).to eq([ broccoli.id ])
  end

  # The failure this class exists for: food the household never bought.
  it "drops an invented ingredient but keeps the rest of the recipe" do
    recipe = ground([ ingredient("Brokkoli", item_id: broccoli.id), ingredient("Parmesan") ])

    expect(recipe[:ingredients].map { |i| i[:name] }).to eq([ "Brokkoli" ])
  end

  it "allows salt, pepper, oil and water, but only as optional" do
    recipe = ground([
      ingredient("Brokkoli", item_id: broccoli.id),
      ingredient("Salz", optional: true), ingredient("Olivenöl", optional: true),
      ingredient("Pepper", optional: false), ingredient("Parmesan", optional: true)
    ])

    expect(recipe[:ingredients].map { |i| i[:name] }).to eq(%w[Brokkoli Salz Olivenöl])
  end

  it "rejects a recipe with nothing real left to cook" do
    expect(ground([ ingredient("Parmesan"), ingredient("Salt", optional: true) ])).to be_nil
  end

  it "rejects a recipe without a title" do
    expect(ground([ ingredient("Brokkoli", item_id: broccoli.id) ], title: " ")).to be_nil
  end

  # "ei" sits inside "weizenbrötchen"; a short word must not match inside a long one.
  it "does not match a short word inside a longer one" do
    expect(ground([ ingredient("Ei") ])).to be_nil
  end

  it "matches a shared stem in a German compound" do
    spinach = create(:item, household: household, display_name: "Babyspinat", canonical_name: "babyspinat")
    recipe = described_class.call(recipe: { "title" => "Spinat", "ingredients" => [ ingredient("Spinat") ],
                                            "steps" => [ "Wilt the Babyspinat." ] },
                                  items: [ spinach ])

    expect(bound_ids(recipe)).to eq([ spinach.id ])
  end

  it "adds a plain step for a required ingredient the method never uses" do
    recipe = ground([ ingredient("Brokkoli", item_id: broccoli.id), ingredient("Weizenbrötchen", item_id: rolls.id) ])

    expect(recipe[:steps]).to eq([ "Cook the Brokkoli in the Milch.", "Add the Weizenbrötchen." ])
  end

  it "writes the added step in the household's language" do
    recipe = I18n.with_locale(:de) { ground([ ingredient("Weizenbrötchen", item_id: rolls.id) ]) }

    expect(recipe[:steps].last).to eq("Weizenbrötchen dazugeben.")
  end

  it "marks and counts the use-first food it cooks with" do
    recipe = ground([ ingredient("Brokkoli", item_id: broccoli.id), ingredient("Milch", item_id: milk.id) ],
                    use_first_ids: [ broccoli.id ])

    expect(recipe[:ingredients].map { |i| i[:use_first] }).to eq([ true, false ])
    expect(recipe[:use_first_count]).to eq(1)
  end
end
