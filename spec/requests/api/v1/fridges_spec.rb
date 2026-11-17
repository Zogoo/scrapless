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

      expect(response).to have_http_status(:success)
    end

    # Two independent stores, so clearing either one alone does not lose the
    # fridge. This is the cookie half.
    # A phone whose boot request failed lands on the welcome screen with its
    # cookie intact. Tapping Skip there must not replace the kitchen.
    it "returns the fridge this browser already holds instead of minting another" do
      post "/api/v1/fridge", params: { name: "Küche" }, as: :json
      first = response.parsed_body

      post "/api/v1/fridge", params: {}, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(first["id"])
      expect(Household.count).to eq(1)
    end

    it "returns the fridge named by the bearer token too" do
      household = create(:household)

      post "/api/v1/fridge", params: {}, headers: fridge_headers(household), as: :json

      expect(response.parsed_body["id"]).to eq(household.uuid)
      expect(Household.count).to eq(1)
    end

    it "still makes a fridge when the token it was sent is unknown" do
      post "/api/v1/fridge", params: {}, headers: { "Authorization" => "Bearer nope" }, as: :json

      expect(response).to have_http_status(:created)
    end

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

  describe "POST /api/v1/fridge/preview" do
    let(:shared) { create(:household, name: "Quiet Kitchen") }

    it "names the kitchen behind a code, and hands out nothing else" do
      post "/api/v1/fridge/preview", params: { join_code: shared.join_code }, as: :json

      expect(response.parsed_body).to eq("name" => "Quiet Kitchen")
      expect(cookies[:scrapless_fridge]).to be_blank
    end

    it "says plainly when a code opens nothing" do
      post "/api/v1/fridge/preview", params: { join_code: "not-a-code" }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    # Otherwise preview would be a free way to test guessed codes.
    it "counts against the same limit as joining" do
      30.times { post "/api/v1/fridge/join", params: { join_code: "x" }, as: :json }
      post "/api/v1/fridge/preview", params: { join_code: shared.join_code }, as: :json

      expect(response).to have_http_status(:too_many_requests)
    end

    # The two limiters used to share one counter, so joins blocked creation.
    it "does not let joins use up the fridge-creation limit" do
      12.times { post "/api/v1/fridge/join", params: { join_code: "x" }, as: :json }
      post "/api/v1/fridge", params: {}, as: :json

      expect(response).to have_http_status(:created)
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

  describe "the weekly notification budget" do
    let(:household) { create(:household) }

    it "is one a week unless the kitchen chooses otherwise" do
      get "/api/v1/fridge", headers: fridge_headers(household)

      expect(response.parsed_body["alerts_per_week"]).to eq(1)
    end

    it "can be raised to three" do
      patch "/api/v1/fridge", params: { alerts_per_week: 3 }, as: :json, headers: fridge_headers(household)

      expect(response.parsed_body["alerts_per_week"]).to eq(3)
    end

    # Doc 3 R5: the cap is a server-side invariant, not a UI preference.
    it "cannot go above three" do
      patch "/api/v1/fridge", params: { alerts_per_week: 7 }, as: :json, headers: fridge_headers(household)

      expect(response).to have_http_status(:unprocessable_content)
      expect(household.reload.alerts_per_week).to eq(1)
    end

    it "is left alone by a rename" do
      household.update!(alerts_per_week: 2)
      patch "/api/v1/fridge", params: { name: "Oma" }, as: :json, headers: fridge_headers(household)

      expect(household.reload.alerts_per_week).to eq(2)
    end
  end
end
