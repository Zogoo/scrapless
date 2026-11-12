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

    # The only unauthenticated endpoint, and the door to the expensive one.
    #
    it "will not let one client mint fridges without limit" do
      11.times { post "/api/v1/fridge", params: {}, as: :json }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body["error"]).to match(/lot of new fridges/i)
    end

    it "is not blocked by the limiter under normal use" do
      3.times { post "/api/v1/fridge", params: {}, as: :json }

      expect(response).to have_http_status(:created)
    end

    # Two independent stores, so clearing either one alone does not lose the
    # fridge. This is the cookie half.
    it "sets a ten-year cookie alongside the token it returns" do
      post "/api/v1/fridge", params: {}, as: :json

      expect(response.headers["Set-Cookie"]).to include("scrapless_fridge")
    end

    it "returns a join code that is not the bearer token" do
      post "/api/v1/fridge", params: {}, as: :json

      body = response.parsed_body
      expect(body["join_code"]).to be_present
      expect(body["join_code"]).not_to eq(body["token"])
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

  describe "POST /api/v1/fridge/join" do
    let(:household) { create(:household, name: "Quiet Kitchen") }

    it "opens the shared kitchen and sets the cookie to it" do
      post "/api/v1/fridge/join", params: { join_code: household.join_code }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["token"]).to eq(household.token)
      expect(response.parsed_body["name"]).to eq("Quiet Kitchen")
      expect(response.parsed_body["join_code"]).to eq(household.join_code)
      expect(response.headers["Set-Cookie"]).to include("scrapless_fridge")

      get "/api/v1/fridge"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(household.uuid)
    end

    it "switches a phone that already had a kitchen" do
      other = create(:household, name: "Other")

      post "/api/v1/fridge/join", params: { join_code: household.join_code },
           headers: fridge_headers(other), as: :json

      expect(response.parsed_body["name"]).to eq("Quiet Kitchen")

      get "/api/v1/fridge"

      expect(response.parsed_body["name"]).to eq("Quiet Kitchen")
    end

    it "does not accept the bearer token as a join code" do
      post "/api/v1/fridge/join", params: { join_code: household.token }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.headers["Set-Cookie"].to_s).not_to include("scrapless_fridge")
    end

    it "does not treat the join code as a bearer token" do
      get "/api/v1/fridge", headers: { "Authorization" => "Bearer #{household.join_code}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an unknown code without setting a cookie" do
      post "/api/v1/fridge/join", params: { join_code: "missing" }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to match(/doesn't open a kitchen/i)
      expect(response.headers["Set-Cookie"].to_s).not_to include("scrapless_fridge")
    end

    it "will not let one client guess join codes without limit" do
      31.times { post "/api/v1/fridge/join", params: { join_code: "missing" }, as: :json }

      expect(response).to have_http_status(:too_many_requests)
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
