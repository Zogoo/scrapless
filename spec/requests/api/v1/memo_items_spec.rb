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
        create(:item, household: household, canonical_name: "hafermilch",
                      acquired_on: Date.current - days_ago)
      end

      get "/api/v1/memo/suggestions", headers: headers

      expect(response.parsed_body.first["name"]).to eq("Hafermilch")
    end
  end
end
