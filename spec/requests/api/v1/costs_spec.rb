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

  # Observed in QA: a fridge with no calls saw the global ledger ("Calls 10").
  # Fridges are free to make, so that was everyone's usage, for anyone.
  it "reports only this kitchen's calls" do
    AiCall.create!(household: create(:household), purpose: "receipt_extract", model: "gpt-5-mini",
                   cost_micros: 2425)
    AiCall.create!(household: nil, purpose: "text_parse", model: "gpt-5-nano", cost_micros: 60)

    get "/api/v1/costs", headers: fridge_headers(household)
    body = response.parsed_body

    expect(body["totals"]).to include("calls" => 0, "usd" => 0.0)
    expect(body["by_purpose"]).to be_empty
  end

  it "does not publish the operator's provider chain or model table" do
    get "/api/v1/costs", headers: fridge_headers(household)

    expect(response.parsed_body.keys).to contain_exactly("mode", "transcribe_usd_per_minute", "totals", "by_purpose")
  end

  # A refused call cost nothing and read nothing; counting it would make a
  # receipt look cheaper than it is.
  it "prices a receipt over the reads that worked" do
    AiCall.create!(household: household, purpose: "receipt_extract", model: "gpt-5-mini", cost_micros: 2400)
    AiCall.create!(household: household, purpose: "receipt_extract", model: "gpt-5-mini", success: false)

    get "/api/v1/costs", headers: fridge_headers(household)

    expect(response.parsed_body["by_purpose"].first["usd_per_call"]).to eq(0.0024)
  end
end
