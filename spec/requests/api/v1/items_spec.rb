require "rails_helper"

RSpec.describe "Api::V1::Items", type: :request do
  before do
    create(:shelf_life_rule, category: "produce", storage: "fridge",
                             days_p50: 5, days_p90: 9, consume_p50: 5)
    create(:shelf_life_rule, category: "produce", storage: "freezer",
                             days_p50: 180, days_p90: 300, consume_p50: 90)
  end

  let(:household) { create(:household) }
  let(:headers) { fridge_headers(household) }

  describe "GET /api/v1/items" do
    it "answers one question: what to do about food today" do
      create(:item, :at_risk, household: household, display_name: "Spinat")
      create(:item, household: household, display_name: "Gouda")

      get "/api/v1/items", headers: headers
      body = response.parsed_body

      expect(body["use_first"].map { |i| i["display_name"] }).to eq([ "Spinat" ])
      expect(body["fine_for_now"].map { |i| i["display_name"] }).to eq([ "Gouda" ])
    end

    # Choice overload kills action: three cards, then a count.
    it "shows at most three things to act on" do
      5.times { |n| create(:item, :at_risk, household: household, display_name: "Item #{n}") }

      get "/api/v1/items", headers: headers

      expect(response.parsed_body["use_first"].size).to eq(3)
    end

    it "retires ghosts by itself rather than handing the user a cleanup list" do
      create(:item, :ghost, household: household)

      get "/api/v1/items", headers: headers

      expect(response.parsed_body["probably_gone"]).to be_empty
      expect(household.items.first.state).to eq("retired")
    end

    it "never sends a precise date it did not read off a label" do
      create(:item, :at_risk, household: household)

      get "/api/v1/items", headers: headers

      headline = response.parsed_body["use_first"].first["headline"]
      expect(headline).not_to match(/\d{4}-\d{2}-\d{2}/)
      expect(headline.downcase).not_to include("expire")
    end

    it "shows only this fridge's food" do
      create(:item, household: create(:household), display_name: "Someone else's")

      get "/api/v1/items", headers: headers

      expect(response.parsed_body["fine_for_now"]).to be_empty
    end
  end

  describe "POST /api/v1/items/:id/resolve" do
    let(:item) { create(:item, :at_risk, household: household) }

    it "ends the task in one tap" do
      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "used" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(item.reload.state).to eq("rescued")
      expect(item.item_events.last.kind).to eq("used")
    end

    it "treats waste as neutral training data, not a confession" do
      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "wasted" }, headers: headers

      expect(item.reload.state).to eq("wasted")
    end

    # Freezing is the cheapest real rescue, and it resets the clock properly
    # rather than scaling the fridge window.
    it "recomputes the window from the freezer table when the item is frozen" do
      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "froze" }, headers: headers

      item.reload
      expect(item.storage).to eq("freezer")
      expect(item.storage_changed_at).to be_present
      expect(item.window_end).to be > Date.current + 100
    end

    # Binary used/gone forces the user to lie, and the lie trains the priors.
    it "records half a spinach as half of it gone, not as a resolved item" do
      item.update!(quantity: 2)
      before = Freshness::PresenceModel.call(item: item)

      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "partial" }, headers: headers

      item.reload
      expect(item.state).to eq("active")
      expect(item.quantity).to eq(1)
      expect(Freshness::PresenceModel.call(item: item)).to be_within(0.01).of(before / 2)
    end

    it "does not make the half you did not eat spoil any faster" do
      original = item.window_end

      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "partial" }, headers: headers

      expect(item.reload.window_end).to eq(original)
    end

    it "lets a no become a snooze rather than a delete" do
      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "snooze", days: 3 }, headers: headers

      expect(item.reload.snoozed_until).to eq(Date.current + 3)
      expect(item.state).to eq("active")
    end

    it "rejects an outcome it does not know" do
      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "eaten-ish" }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/items/:id" do
    # Correction has to be cheaper than capture, and it has to pay for itself.
    it "teaches the dictionary so the same receipt line parses free next time" do
      item = create(:item, household: household, raw_text: "GURK.SAL.STCK",
                           display_name: "Gurk Sal Stck")

      patch "/api/v1/items/#{item.id}",
            params: { item: { display_name: "Salatgurke", canonical_name: "salatgurke" } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(ProductAlias.lookup("GURK.SAL.STCK")&.canonical_name).to eq("salatgurke")
    end
  end
end
