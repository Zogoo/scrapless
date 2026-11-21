require "rails_helper"

RSpec.describe Recipes::Suggest do
  let(:household) { create(:household) }

  def recipe(title, *items)
    {
      "title" => title, "minutes" => 10,
      "ingredients" => items.map { |item| { "item_id" => item.id, "name" => item.display_name, "amount" => nil, "optional" => false } },
      "steps" => [ "Cook the #{items.map(&:display_name).join(' and ')}." ]
    }
  end

  def model_answers(*recipes)
    allow(Ai::RecipeWriter).to receive(:call).and_return("recipes" => recipes)
  end

  def suggest(**kwargs)
    described_class.call(household: household, meal: "dinner", **kwargs)
  end

  it "refuses a meal that is not breakfast, lunch or dinner" do
    create(:item, household: household)
    expect(Ai::RecipeWriter).not_to receive(:call)

    expect { suggest(meal: "snack") }.to raise_error(described_class::UnknownMeal)
  end

  it "does not call the model for an empty kitchen" do
    expect(Ai::RecipeWriter).not_to receive(:call)

    expect(suggest.recipes).to eq([])
  end

  it "does not use up the meal when there was nothing to cook" do
    suggest
    create(:item, household: household)
    model_answers

    expect(suggest.cached).to be(false)
    expect(Ai::RecipeWriter).to have_received(:call).once
  end

  # Observed: a full kitchen, and breakfast said "nothing to cook" all day.
  # An empty answer was stored like a real one, so every later tap that day
  # got it back without asking again.
  it "does not keep an empty answer for the day; the next tap asks again" do
    eggs = create(:item, household: household, display_name: "Eier", canonical_name: "eier")
    model_answers
    expect(suggest(meal: "breakfast").recipes).to eq([])

    model_answers(recipe("Rührei", eggs))
    result = suggest(meal: "breakfast")

    expect(result.recipes.map { |r| r[:title] }).to eq([ "Rührei" ])
    expect(result.cached).to be(false)
  end

  it "does not keep an answer whose every recipe was thrown out" do
    create(:item, household: household, display_name: "Eier", canonical_name: "eier")
    model_answers({ "title" => "Pancakes", "minutes" => 10, "steps" => [ "Mix." ],
                    "ingredients" => [ { "item_id" => nil, "name" => "flour", "amount" => nil, "optional" => false } ] })

    expect(suggest(meal: "breakfast").recipes).to eq([])
    expect(household.meal_suggestions).to be_empty
  end

  it "shows the model the food most at risk first, flagged as use-first" do
    fresh = create(:item, household: household, display_name: "Nudeln", canonical_name: "nudeln")
    urgent = create(:item, :at_risk, household: household, display_name: "Brokkoli")
    model_answers

    suggest

    expect(Ai::RecipeWriter).to have_received(:call) do |pantry:, **|
      expect(pantry.map { |entry| entry[:id] }).to eq([ urgent.id, fresh.id ])
      expect(pantry.first[:priority]).to eq("use_first")
      expect(pantry.last).not_to have_key(:priority)
    end
  end

  # "Hähnchenbrustfilet" and "chicken breast" were offered as two ingredients.
  it "offers each food once, however many names and packs it has" do
    chicken = Product.for("chicken breast")
    first = create(:item, :at_risk, household: household, display_name: "Hähnchenbrustfilet", product: chicken)
    create(:item, household: household, display_name: "Chicken breast", canonical_name: "chicken breast",
                  product: chicken)
    model_answers

    suggest

    expect(Ai::RecipeWriter).to have_received(:call) do |pantry:, **|
      expect(pantry.map { |entry| entry[:id] }).to eq([ first.id ])
    end
  end

  it "names the amount's unit in the meal's language" do
    create(:item, :at_risk, household: household, display_name: "Paprika", quantity: 3, unit: "piece")
    model_answers

    suggest(locale: :de)

    expect(Ai::RecipeWriter).to have_received(:call) do |pantry:, **|
      expect(pantry.first[:amount]).to eq("3 Stück")
    end
  end

  # Food we have stopped believing in must not become dinner.
  it "leaves out food that is probably already gone" do
    create(:item, :ghost, household: household, display_name: "Old salad")
    kept = create(:item, household: household)
    model_answers

    suggest

    expect(Ai::RecipeWriter).to have_received(:call) do |pantry:, **|
      expect(pantry.map { |entry| entry[:id] }).to eq([ kept.id ])
    end
  end

  it "returns at most three recipes, the ones rescuing the most use-first food first" do
    urgent = create(:item, :at_risk, household: household, display_name: "Brokkoli")
    other = create(:item, household: household, display_name: "Nudeln", canonical_name: "nudeln")
    model_answers(recipe("Plain pasta", other), recipe("Broccoli pasta", urgent, other),
                  recipe("Pasta two", other), recipe("Pasta three", other))

    titles = suggest.recipes.map { |r| r[:title] }

    expect(titles).to eq([ "Broccoli pasta", "Plain pasta", "Pasta two" ])
  end

  describe "caching" do
    let!(:item) { create(:item, household: household) }

    before { model_answers(recipe("Brokkoli pan", item)) }

    it "answers a repeat tap for that meal without calling the model again" do
      first = suggest
      second = suggest

      expect(Ai::RecipeWriter).to have_received(:call).once
      expect([ first.cached, second.cached ]).to eq([ false, true ])
      expect(second.recipes).to eq(first.recipes)
    end

    it "does not ask again the same day when the food in the kitchen changes" do
      suggest
      create(:item, household: household, display_name: "Milch", canonical_name: "milch")

      expect(suggest.cached).to be(true)
      expect(Ai::RecipeWriter).to have_received(:call).once
    end

    it "asks again for a different meal" do
      suggest

      expect(suggest(meal: "breakfast").cached).to be(false)
      expect(Ai::RecipeWriter).to have_received(:call).twice
    end

    it "asks again the next day" do
      suggest

      expect(suggest(on: Date.current + 1).cached).to be(false)
      expect(Ai::RecipeWriter).to have_received(:call).twice
    end

    # Observed in QA: after switching to German, the day's English dinner was
    # served until midnight. Still once a day — once per language the kitchen
    # actually asks in, which for most kitchens is one.
    it "writes the meal again for a phone in another language, once" do
      suggest(locale: :en)
      german = suggest(locale: :de)
      suggest(locale: :de)

      expect(Ai::RecipeWriter).to have_received(:call).twice
      expect(german.cached).to be(false)
      expect(suggest(locale: :en).cached).to be(true)
    end

    it "does not share answers between fridges" do
      other = create(:household)
      create(:item, household: other)

      suggest
      described_class.call(household: other, meal: "dinner")

      expect(Ai::RecipeWriter).to have_received(:call).twice
    end
  end

  describe "the hourly limit" do
    before do
      create(:item, household: household)
      allow(Ai::Config).to receive(:live?).and_return(true)
      model_answers
    end

    def log_calls(count, at: Time.current)
      count.times do
        AiCall.create!(household: household, purpose: "recipe_suggest", model: "gpt-5-nano", created_at: at)
      end
    end

    it "stops a fridge that has used its model calls for the hour" do
      log_calls(described_class::MAX_CALLS_PER_HOUR)

      expect { suggest }.to raise_error(described_class::TooMany)
    end

    it "only counts the last hour" do
      log_calls(described_class::MAX_CALLS_PER_HOUR, at: 2.hours.ago)

      expect { suggest }.not_to raise_error
    end

    it "still answers from the cache once the limit is reached" do
      model_answers(recipe("Gemüsepfanne", household.items.first)) # only an answer with recipes is kept
      suggest
      log_calls(described_class::MAX_CALLS_PER_HOUR)

      expect(suggest.cached).to be(true)
    end
  end

  describe "the household's food settings" do
    let!(:eggs) { create(:item, household: household, display_name: "Eier", canonical_name: "eier") }
    let(:router) { instance_double(Ai::Router, json_completion: { "recipes" => [ recipe("Rührei", eggs) ] }) }

    before do
      allow(Ai::Config).to receive(:live?).and_return(true)
      allow(Ai::Router).to receive(:new).and_return(router)
    end

    def system_prompt
      suggest(meal: "breakfast")
      prompt = nil
      expect(router).to have_received(:json_completion) { |messages:, **| prompt = messages.first[:content] }
      prompt
    end

    it "makes vegan a hard rule" do
      household.update!(diet: "vegan")

      expect(system_prompt).to include("hard: never break them", "Vegan: never use meat", "eggs, milk")
    end

    it "spells out what leaving out pork means" do
      household.update!(excluded_foods: [ "Schwein" ])

      expect(system_prompt).to include("Never use pork or pork products (bacon, ham")
    end

    it "adds no rule for a kitchen that eats everything" do
      household.update!(diet: "all")

      expect(system_prompt).not_to include("This household's rules")
    end

    # Typed by the household: it names a food and must not read as an instruction.
    it "quotes a food the household typed" do
      household.update!(excluded_foods: [ "Koriander" ])

      expect(system_prompt).to include('Never use this food or anything made from it: "Koriander".')
    end

    it "does not show today's recipes again after the diet or the list changed" do
      model_answers(recipe("Rührei", eggs))
      allow(Ai::Router).to receive(:new).and_call_original
      expect(suggest(meal: "breakfast").cached).to be(false)
      expect(suggest(meal: "breakfast").cached).to be(true)

      household.update!(diet: "vegan")
      expect(suggest(meal: "breakfast").cached).to be(false)

      household.update!(excluded_foods: [ "Fisch" ])
      expect(suggest(meal: "breakfast").cached).to be(false)
    end
  end

  describe "the Brotbox" do
    include ActiveSupport::Testing::TimeHelpers

    let!(:cheese) { create(:item, household: household, display_name: "Käse", canonical_name: "käse") }

    before { household.update!(brotbox_count: 2, timezone: "Europe/Berlin") }

    def berlin(text) = ActiveSupport::TimeZone["Europe/Berlin"].parse(text)

    {
      "2026-11-18 09:00" => "2026-11-18", # Wednesday morning: today's
      "2026-11-18 17:00" => "2026-11-19", # Wednesday evening: Thursday's
      "2026-11-20 17:00" => "2026-11-23", # Friday evening: Monday's
      "2026-11-21 10:00" => "2026-11-23"  # Saturday: Monday's
    }.each do |now, school_day|
      it "plans #{now} (Berlin) for #{school_day}" do
        expect(described_class.school_day(household, berlin(now))).to eq(Date.parse(school_day))
      end
    end

    it "is stored under the school day it is for" do
      model_answers(recipe("Käsebrot-Häppchen", cheese))

      travel_to(berlin("2026-11-18 17:00")) { expect(suggest(meal: "brotbox").for_date).to eq(Date.new(2026, 11, 19)) }
      travel_to(berlin("2026-11-19 08:00")) do
        result = suggest(meal: "brotbox")
        expect(result.cached).to be(true)
        expect(result.for_date).to eq(Date.new(2026, 11, 19))
      end
    end

    it "is not a meal for a kitchen that packs none, or never said" do
      [ 0, nil ].each do |count|
        household.update!(brotbox_count: count)
        expect { suggest(meal: "brotbox") }.to raise_error(described_class::UnknownMeal)
      end
    end

    describe "the prompt" do
      let(:router) { instance_double(Ai::Router, json_completion: { "recipes" => [ recipe("Häppchen", cheese) ] }) }

      before do
        allow(Ai::Config).to receive(:live?).and_return(true)
        allow(Ai::Router).to receive(:new).and_return(router)
      end

      def system_prompt
        suggest(meal: "brotbox")
        prompt = nil
        expect(router).to have_received(:json_completion) { |messages:, **| prompt = messages.first[:content] }
        prompt
      end

      it "asks for a cold, quick, nut-free lunchbox for the household's number of boxes" do
        expect(system_prompt).to include("school lunchbox", "for 2 box(es)", "eaten cold", "No reheating",
                                         "at most 10 minutes", "Finger food", "Never use nuts",
                                         "mayonnaise salads")
      end

      it "still follows the household's diet" do
        household.update!(diet: "vegan")

        expect(system_prompt).to include("Never use nuts", "Vegan: never use meat")
      end
    end
  end
end
