require "rails_helper"

RSpec.describe "Api::V1::Costs", type: :request do
  let(:household) { create(:household) }

  # The unit-economics claim for this MVP is "a capture costs a fraction of a
  # cent". That should be falsifiable by anyone using the app, not just by
  # whoever reads the invoice.
  it "reports what the model calls have actually cost" do
    AiCall.create!(household: household, purpose: "receipt_extract", model: "gpt-5-mini",
                   input_tokens: 2500, output_tokens: 900, cost_micros: 2425, duration_ms: 1800)

    get "/api/v1/costs", headers: fridge_headers(household)
    body = response.parsed_body

    expect(body["totals"]["calls"]).to eq(1)
    expect(body["totals"]["usd"]).to be_within(0.0001).of(0.002425)
    expect(body["by_purpose"].first).to include("purpose" => "receipt_extract", "calls" => 1)
    expect(body["mode"]).to eq("stub")
  end

  it "says which model each job is pointed at" do
    get "/api/v1/costs", headers: fridge_headers(household)

    expect(response.parsed_body["models"]["receipt_extract"]["name"]).to eq("gpt-5-mini")
  end
end
