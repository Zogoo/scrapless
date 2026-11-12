require "rails_helper"
require "net/http"

RSpec.describe Ai::RecipeWriter do
  let(:pantry) do
    [ { id: 1, name: "Brokkoli", priority: "use_first" }, { id: 2, name: "Milch" }, { id: 3, name: "Nudeln" } ]
  end

  it "returns nothing for an empty kitchen" do
    expect(described_class.call(pantry: [])).to eq("recipes" => [])
  end

  # The stub is the product with no key configured, so it has to cook with the
  # household's own food rather than a canned list.
  it "builds the stub answer from the household's own food" do
    result = described_class.call(pantry: pantry)

    ids = result["recipes"].first["ingredients"].filter_map { |i| i["item_id"] }
    expect(ids).to eq([ 1, 2, 3 ])
  end

  context "when live" do
    let(:household) { create(:household) }

    around do |example|
      ENV["AI_MODE"] = "live"
      ENV["OPENAI_API_KEY"] = "test-key"
      example.run
    ensure
      ENV["AI_MODE"] = "stub"
      ENV.delete("OPENAI_API_KEY")
    end

    def stub_transport
      body = {
        "choices" => [ { "message" => { "content" => '{"recipes":[]}' } } ],
        "usage" => { "prompt_tokens" => 400, "completion_tokens" => 300 }
      }.to_json
      response = instance_double(Net::HTTPResponse, code: "200", body: body)
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(Net::HTTP).to receive(:start).and_return(response)
    end

    it "bills the call to the household on the cheap text tier" do
      stub_transport
      described_class.call(pantry: pantry, household: household)

      expect(AiCall.last).to have_attributes(purpose: "recipe_suggest", model: "gpt-5-nano",
                                             household_id: household.id, success: true)
    end

    it "shows the model the exact list and asks for the household's language" do
      router = instance_double(Ai::Router, json_completion: { "recipes" => [] })
      allow(Ai::Router).to receive(:new).and_return(router)

      described_class.call(pantry: pantry, household: household, locale: :de)

      expect(router).to have_received(:json_completion) do |purpose:, messages:, **|
        expect(purpose).to eq(:recipe_suggest)
        expect(messages.first[:content]).to include("Write titles and steps in German")
        expect(JSON.parse(messages.last[:content]).map { |e| e["id"] }).to eq([ 1, 2, 3 ])
      end
    end
  end
end
