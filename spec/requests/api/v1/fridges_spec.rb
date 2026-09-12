require "rails_helper"

RSpec.describe "Api::V1::Fridges", type: :request do
  describe "POST /api/v1/fridge" do
    it "creates a fridge with no account, no email and no password" do
      post "/api/v1/fridge", params: { name: "Küche" }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("id", "name" => "Küche", "token" => be_present)
    end

    it "names an unnamed fridge itself, because 'skip' has to lead somewhere" do
      post "/api/v1/fridge", params: {}, as: :json

      expect(response.parsed_body["name"]).to be_present
    end

    # Two independent stores, so clearing either one alone does not lose the
    # fridge. This is the cookie half.
    it "sets a ten-year cookie alongside the token it returns" do
      post "/api/v1/fridge", params: {}, as: :json

      expect(response.headers["Set-Cookie"]).to include("crisper_fridge")
    end
  end

  describe "GET /api/v1/fridge" do
    let(:household) { create(:household) }

    it "identifies the fridge from the bearer token" do
      get "/api/v1/fridge", headers: fridge_headers(household)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq(household.name)
    end

    it "identifies the fridge from the cookie when there is no token" do
      post "/api/v1/fridge", params: { name: "Cookie Fridge" }, as: :json
      get "/api/v1/fridge"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("Cookie Fridge")
    end

    it "refuses an unknown token rather than quietly making a new fridge" do
      get "/api/v1/fridge", headers: { "Authorization" => "Bearer nonsense" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/fridge" do
    it "erases the household outright" do
      household = create(:household)
      create(:item, household: household)

      delete "/api/v1/fridge", headers: fridge_headers(household)

      expect(response).to have_http_status(:no_content)
      expect(Household.count).to eq(0)
      expect(Item.count).to eq(0)
    end
  end
end
