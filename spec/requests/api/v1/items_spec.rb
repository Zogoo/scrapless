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

    it "tells a brand-new kitchen it has nothing captured yet" do
      get "/api/v1/items", headers: headers
      expect(response.parsed_body["has_captured"]).to be(false)

      create(:capture, household: household)
      get "/api/v1/items", headers: headers
      expect(response.parsed_body["has_captured"]).to be(true)
    end

    it "shows only this fridge's food" do
      create(:item, household: create(:household), display_name: "Someone else's")

      get "/api/v1/items", headers: headers

      expect(response.parsed_body["fine_for_now"]).to be_empty
    end

    it "shows who added the food when the phone said so" do
      create(:item, household: household, display_name: "Milch", added_by_name: "Mama")

      get "/api/v1/items", headers: headers

      listed = response.parsed_body.values_at("use_first", "fine_for_now", "probably_gone").flatten
      milch = listed.find { |item| item["display_name"] == "Milch" }
      expect(milch["added_by_name"]).to eq("Mama")
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

    it "records the amount still left when a partly used pack is thrown away" do
      item.update!(amount_left: 0.5, quantity: 1)

      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "wasted" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(item.reload.quantity.to_f).to eq(0.5)
      expect(item.amount_left).to eq(0.5)
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

    it "moves food to the place it was sent" do
      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "moved", to: "pantry" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["storage"]).to eq("pantry")
    end

    it "says so when the place is not one of the kitchen's" do
      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "moved", to: "garage" }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(item.reload.storage).to eq("fridge")
    end

    # Binary used/gone forces the user to lie, and the lie trains the priors.
    it "records half a spinach as half of it gone, not as a resolved item" do
      item.update!(quantity: 2)
      before = Freshness::PresenceModel.call(item: item)

      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "partial" }, headers: headers

      item.reload
      expect(item.state).to eq("active")
      expect(item.quantity).to eq(1)
      expect(item.amount_left).to eq(0.5)
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

  describe "DELETE /api/v1/items/:id" do
    # A line removed on the review screen was read wrong; what the model said
    # about it must not stay in the dictionary, nor count as a vote.
    it "takes back what the model taught this kitchen about the line" do
      item = create(:item, household: household, raw_text: "1 x Filetsteak")
      create(:product_alias, household: household, raw_text: "x filetsteak", canonical_name: "Filet steak",
                             category: "meat_fish", source: "ai")
      kept = create(:product_alias, household: household, raw_text: "brot", canonical_name: "Brot",
                                    category: "bakery", source: "correction")

      delete "/api/v1/items/#{item.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(ProductAlias.where(household: household)).to contain_exactly(kept)
    end
  end

  describe "POST /api/v1/items/:id/undo" do
    let(:item) { create(:item, household: household) }

    it "takes back the tap just made" do
      post "/api/v1/items/#{item.id}/resolve", params: { outcome: "wasted" }, headers: headers
      post "/api/v1/items/#{item.id}/undo", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["state"]).to eq("active")
    end

    it "says so, plainly, when there is nothing to undo" do
      post "/api/v1/items/#{item.id}/undo", headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/can't be undone/)
    end

    it "cannot undo another kitchen's food" do
      other = create(:item)
      post "/api/v1/items/#{other.id}/undo", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/items/:id/revert_open" do
    it "puts the unopened window back when the slider returns to where it started" do
      potato = create(:item, household: household, category: "produce", display_name: "Potato",
                             canonical_name: "potato", acquired_on: Date.current,
                             window_start: Date.current + 4, window_end: Date.current + 9)

      post "/api/v1/items/#{potato.id}/resolve",
           params: { outcome: "opened", source: "slider", start_percent: 100 }, headers: headers
      post "/api/v1/items/level", params: { ids: [ potato.id ], level: 0.5 }, headers: headers
      post "/api/v1/items/#{potato.id}/revert_open", params: { percent: 100 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("opened_on" => nil,
                                              "window_start" => (Date.current + 4).iso8601,
                                              "window_end" => (Date.current + 9).iso8601)
    end

    it "requires the percent the thumb was released at" do
      potato = create(:item, household: household)

      post "/api/v1/items/#{potato.id}/revert_open", headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses a kitchen that has not signed in" do
      potato = create(:item, household: household)

      post "/api/v1/items/#{potato.id}/revert_open", params: { percent: 100 }

      expect(response).to have_http_status(:unauthorized)
    end

    it "cannot restore another kitchen's food" do
      other = create(:item)

      post "/api/v1/items/#{other.id}/revert_open", params: { percent: 100 }, headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/items/level" do
    # Two phones on one kitchen moving the same slider at once.
    it "answers a conflicting change with a retryable 409, not a crash" do
      allow(Inventory::SetLevel).to receive(:call).and_raise(ActiveRecord::StaleObjectError)

      post "/api/v1/items/level", params: { ids: [ 1 ], level: 1 }, headers: headers

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to include("retryable" => true, "error" => /latest/)
    end

    it "uses the line up at 0% and undo puts that pack back" do
      milk = create(:item, household: household, amount_left: 0.25)

      post "/api/v1/items/level", params: { ids: [ milk.id ], level: 0 }, headers: headers
      expect(milk.reload.state).to eq("rescued")

      post "/api/v1/items/#{milk.id}/undo", headers: headers

      expect(response).to have_http_status(:ok)
      expect(milk.reload).to have_attributes(state: "active", amount_left: 0.25)
    end

    it "sets how much is left across every pack on one Kitchen line" do
      old = create(:item, :at_risk, household: household)
      fresh = create(:item, household: household)

      post "/api/v1/items/level", params: { ids: [ old.id, fresh.id ], level: 1.25 }, headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body["items"]
      expect(body.map { |i| i["id"] }).to eq([ old.id, fresh.id ])
      expect(body.map { |i| i["amount_left"] }).to eq([ 0.25, 1.0 ])
    end

    it "requires a level" do
      post "/api/v1/items/level", params: { ids: [ 1 ] }, headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "PATCH /api/v1/items/:id input limits" do
    let(:item) { create(:item, household: household) }

    # Observed in QA: a 5,000-character name, category "weapons" and quantity
    # -5 were all stored.
    [
      [ "an endless name", { display_name: "x" * 121 } ],
      [ "a made-up category", { category: "weapons" } ],
      [ "a negative quantity", { quantity: -5 } ]
    ].each do |label, change|
      it "refuses #{label}, in a plain sentence" do
        patch "/api/v1/items/#{item.id}", params: { item: change }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to eq(I18n.t("record.invalid"))
      end
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
      expect(ProductAlias.lookup("GURK.SAL.STCK", household: household)&.canonical_name).to eq("salatgurke")
    end

    # Fridges are free and anonymous, so one of them renaming a line must not
    # rename it for every kitchen (doc 5 §5.6, doc 7 B6).
    it "keeps the correction inside the kitchen that made it" do
      create(:product_alias, raw_text: "milch", canonical_name: "Milch", category: "dairy", seeded: true)
      item = create(:item, household: household, raw_text: "MILCH", display_name: "Milch")

      patch "/api/v1/items/#{item.id}",
            params: { item: { display_name: "Something rude", canonical_name: "something rude" } },
            headers: headers, as: :json

      expect(ProductAlias.lookup("MILCH", household: household).canonical_name).to eq("something rude")
      expect(ProductAlias.lookup("MILCH", household: create(:household)).canonical_name).to eq("Milch")
      expect(ProductAlias.shared.find_by(raw_text: "milch").canonical_name).to eq("Milch")
    end
  end
end
