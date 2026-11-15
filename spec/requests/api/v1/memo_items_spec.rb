require "rails_helper"

RSpec.describe "Api::V1::MemoItems", type: :request do
  let(:household) { create(:household) }
  let(:headers) { fridge_headers(household) }

  it "lists the memo with suggestions attached, so the list is never empty" do
    create(:memo_item, household: household, name: "Butter")

    get "/api/v1/memo", headers: headers
    body = response.parsed_body

    expect(body["items"].map { |i| i["name"] }).to eq([ "Butter" ])
    expect(body["suggestions"]).not_to be_empty
  end

  it "adds a line" do
    post "/api/v1/memo", params: { name: "Kaffee" }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(household.memo_items.pluck(:name)).to eq([ "Kaffee" ])
  end

  it "attributes a line to the name on the phone" do
    post "/api/v1/memo", params: { name: "Kaffee" },
         headers: headers.merge("X-Actor-Name" => "Mama"), as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["added_by_name"]).to eq("Mama")
    expect(household.memo_items.last.added_by_name).to eq("Mama")
  end

  it "leaves the name blank when the phone has not chosen one" do
    post "/api/v1/memo", params: { name: "Kaffee" }, headers: headers, as: :json

    expect(household.memo_items.last.added_by_name).to be_nil
  end

  it "attributes every line of a dictation to the same name" do
    post "/api/v1/memo/dictate", params: { transcript: "milk and bread" },
         headers: headers.merge("X-Actor-Name" => "Oma%20Inge"), as: :json

    expect(response).to have_http_status(:created)
    expect(household.memo_items.pluck(:added_by_name).uniq).to eq([ "Oma Inge" ])
  end

  it "keeps a very long name from failing the line" do
    post "/api/v1/memo", params: { name: "Kaffee", added_by: "M" * 80 }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(household.memo_items.last.added_by_name).to eq("M" * 40)
  end

  # The memo is the one place where cost per line should be exactly zero, so
  # dictation splits locally and never reaches a model.
  it "splits a spoken sentence into lines without calling a model" do
    expect {
      post "/api/v1/memo/dictate", params: { transcript: "milk, bread and coffee" },
           headers: headers, as: :json
    }.not_to change(AiCall, :count)

    expect(response).to have_http_status(:created)
    expect(household.memo_items.pluck(:name)).to eq(%w[Milk Bread Coffee])
  end

  it "ticks a line off" do
    memo = create(:memo_item, household: household)

    patch "/api/v1/memo/#{memo.id}", params: { memo_item: { done: true } },
          headers: headers, as: :json

    expect(memo.reload.done).to be(true)
    expect(memo.done_at).to be_present
  end

  describe "GET /api/v1/memo/suggestions" do
    it "autosuggests as the user types" do
      get "/api/v1/memo/suggestions", params: { q: "cof" }, headers: headers

      expect(response.parsed_body.map { |s| s["name"] }).to eq([ "Coffee" ])
    end

    it "ranks what this household actually buys above the generic staples" do
      [ 21, 14, 7 ].each do |days_ago|
        create(:item, household: household, canonical_name: "hafermilch", display_name: "Hafermilch",
                      acquired_on: Date.current - days_ago)
      end

      get "/api/v1/memo/suggestions", headers: headers

      expect(response.parsed_body.first["name"]).to eq("Hafermilch")
    end
  end

  describe "QA fixes" do
    # Two phones adding the same thing to one shared list.
    it "keeps one open line per name" do
      post "/api/v1/memo", params: { name: "gouda" }, headers: headers
      post "/api/v1/memo", params: { name: "Gouda" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(household.memo_items.pluck(:name)).to eq([ "Gouda" ])
    end

    it "does not add a spoken line that is already open" do
      create(:memo_item, household: household, name: "Milch")

      post "/api/v1/memo/dictate", params: { transcript: "milch und brot" }, headers: headers

      expect(household.memo_items.order(:id).pluck(:name)).to eq(%w[Milch Brot])
    end

    it "clears every bought line in one go, and only those" do
      create(:memo_item, household: household, name: "Eier", done: true)
      create(:memo_item, household: household, name: "Brot")

      delete "/api/v1/memo/clear_done", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(household.memo_items.pluck(:name)).to eq([ "Brot" ])
    end

    it "stops suggesting a dismissed name" do
      create(:item, household: household, canonical_name: "thing17", display_name: "Thing17",
                    state: "rescued")

      post "/api/v1/memo/dismiss_suggestion", params: { name: "Thing17" }, headers: headers

      expect(response.parsed_body.map { |s| s["name"] }).not_to include("Thing17")
    end
  end
end
