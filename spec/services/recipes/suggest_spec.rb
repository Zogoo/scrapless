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

    it "shows the stored answer when the same meal is asked in another language" do
      suggest(locale: :en)
      second = suggest(locale: :de)

      expect(Ai::RecipeWriter).to have_received(:call).once
      expect(second.cached).to be(true)
      expect(second.recipes).to eq(suggest(locale: :en).recipes)
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
      suggest
      log_calls(described_class::MAX_CALLS_PER_HOUR)

      expect(suggest.cached).to be(true)
    end
  end
end
