require "rails_helper"

RSpec.describe Ai::Client do
  let(:household) { create(:household) }

  # The transport is stubbed rather than mocked at the method level: the point of
  # these examples is that token accounting and the AiCall row are written
  # correctly from a real provider response shape.
  def stub_response(status: "200", body:)
    response = instance_double(Net::HTTPResponse, code: status, body: body.to_json)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(status == "200")
    allow(Net::HTTP).to receive(:start).and_return(response)
  end

  around do |example|
    ENV["OPENAI_API_KEY"] = "test-key"
    example.run
    ENV.delete("OPENAI_API_KEY")
  end

  describe "#json_completion" do
    let(:completion) do
      {
        "choices" => [ { "message" => { "content" => '{"kind":"receipt"}' } } ],
        "usage" => { "prompt_tokens" => 2500, "completion_tokens" => 900 }
      }
    end

    it "returns the parsed JSON the model produced" do
      stub_response(body: completion)

      result = described_class.new(household: household).json_completion(
        purpose: :receipt_extract, messages: [], schema: {}
      )

      expect(result).to eq("kind" => "receipt")
    end

    # The cost report is a headline claim of this build; if this row is not
    # written, the claim is unfalsifiable.
    it "bills the call against the fridge that made it" do
      stub_response(body: completion)

      expect {
        described_class.new(household: household).json_completion(
          purpose: :receipt_extract, messages: [], schema: {}
        )
      }.to change(AiCall, :count).by(1)

      call = AiCall.last
      expect(call.household).to eq(household)
      expect(call.model).to eq("gpt-5-mini")
      expect(call.input_tokens).to eq(2500)
      expect(call.output_tokens).to eq(900)
      expect(call.cost_usd).to be_within(0.0005).of(0.0024)
      expect(call.success).to be(true)
    end

    it "records a failed call too, so the ledger cannot under-report" do
      stub_response(status: "500", body: { "error" => "upstream exploded" })

      expect {
        described_class.new(household: household).json_completion(
          purpose: :receipt_extract, messages: [], schema: {}
        )
      }.to raise_error(described_class::Error)

      expect(AiCall.last).to have_attributes(success: false, purpose: "receipt_extract")
    end

    it "raises a clear error rather than calling out with no key" do
      ENV.delete("OPENAI_API_KEY")

      expect {
        described_class.new.json_completion(purpose: :text_parse, messages: [], schema: {})
      }.to raise_error(described_class::MissingKey)
    end

    it "treats an empty completion as a failure rather than an empty basket" do
      stub_response(body: { "choices" => [ { "message" => { "content" => "" } } ], "usage" => {} })

      expect {
        described_class.new.json_completion(purpose: :text_parse, messages: [], schema: {})
      }.to raise_error(described_class::Error, /empty completion/)
    end

    it "turns a network failure into its own error class, not a raw socket error" do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect {
        described_class.new.json_completion(purpose: :text_parse, messages: [], schema: {})
      }.to raise_error(described_class::Error, /transport/)
    end
  end

  describe "#transcribe" do
    it "bills audio by the minute, not by the token" do
      stub_response(body: { "text" => "milk and broccoli" })

      text = described_class.new(household: household).transcribe(
        io: StringIO.new("audio"), filename: "a.webm",
        content_type: "audio/webm", duration_seconds: 30
      )

      expect(text).to eq("milk and broccoli")
      expect(AiCall.last.audio_seconds).to eq(30)
      expect(AiCall.last.cost_usd).to be_within(0.0001).of(0.0015)
    end
  end
end
