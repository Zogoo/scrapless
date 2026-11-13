require "rails_helper"

RSpec.describe "Api::V1::Recipes", type: :request do
  let(:household) { create(:household) }
  let(:headers) { fridge_headers(household) }

  describe "POST /api/v1/recipes/suggest" do
    it "needs a fridge" do
      post "/api/v1/recipes/suggest"

      expect(response).to have_http_status(:unauthorized)
    end

    it "suggests recipes built only from this kitchen's food, use-first food flagged" do
      urgent = create(:item, :at_risk, household: household, display_name: "🥦 Brokkoli")
      create(:item, household: household, display_name: "Nudeln", canonical_name: "nudeln")
      create(:item, household: create(:household), display_name: "Someone else's cheese", canonical_name: "cheese")

      post "/api/v1/recipes/suggest", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      ingredients = body["recipes"].flat_map { |r| r["ingredients"] }
      expect(body["mode"]).to eq("stub")
      expect(ingredients.map { |i| i["name"] }).to include("Brokkoli", "Nudeln")
      expect(ingredients.map { |i| i["name"] }).not_to include("Someone else's cheese")
      expect(ingredients.find { |i| i["item_id"] == urgent.id }["use_first"]).to be(true)
    end

    it "answers an empty kitchen with no recipes rather than an error" do
      post "/api/v1/recipes/suggest", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["recipes"]).to eq([])
    end

    it "answers a repeat tap from the cache" do
      create(:item, household: household)

      2.times { post "/api/v1/recipes/suggest", headers: headers }

      expect(response.parsed_body["cached"]).to be(true)
    end

    it "says so in recipe terms when the fridge has asked too often this hour" do
      create(:item, household: household)
      allow(Recipes::Suggest).to receive(:call).and_raise(Recipes::Suggest::TooMany)

      post "/api/v1/recipes/suggest", headers: headers

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body["error"]).to eq(I18n.t("recipes.too_many"))
    end

    context "when the day's AI budget is spent" do
      around do |example|
        ENV["AI_MODE"] = "live"
        ENV["OPENAI_API_KEY"] = "test-key"
        ENV["AI_DAILY_BUDGET_USD"] = "0.01"
        example.run
      ensure
        ENV["AI_MODE"] = "stub"
        %w[OPENAI_API_KEY AI_DAILY_BUDGET_USD].each { |k| ENV.delete(k) }
      end

      it "never calls out, and points back at the list instead of a dead end" do
        create(:item, household: household)
        AiCall.create!(purpose: "receipt_extract", model: "gpt-5-mini", cost_micros: 20_000)
        expect(Net::HTTP).not_to receive(:start)

        post "/api/v1/recipes/suggest", headers: headers

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body).to include("error" => I18n.t("recipes.ai_unavailable"), "retryable" => false)
      end
    end
  end
end
