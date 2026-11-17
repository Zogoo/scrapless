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

    # A reply cut off by the token budget is not JSON. It must surface as a
    # readable failure ("try again"), not escape every rescue as a 500.
    it "treats a truncated answer as unreadable, and bills it once" do
      stub_response(body: {
        "choices" => [ { "message" => { "content" => '{"kind":"receipt","lines":[{"raw' },
                         "finish_reason" => "length" } ],
        "usage" => { "prompt_tokens" => 2500, "completion_tokens" => 900 }
      })

      expect {
        described_class.new(household: household).json_completion(
          purpose: :receipt_extract, messages: [], schema: {}
        )
      }.to raise_error(described_class::Error, /unparseable completion \(finish_reason=length\)/)
        .and change(AiCall, :count).by(1)

      expect(AiCall.last).to have_attributes(success: false, output_tokens: 900)
      expect(AiCall.last.cost_micros).to be_positive
    end

    it "writes one row, not two, for an empty answer" do
      stub_response(body: { "choices" => [ { "message" => { "content" => "" } } ], "usage" => {} })

      expect {
        described_class.new.json_completion(purpose: :text_parse, messages: [], schema: {})
      }.to raise_error(described_class::Error).and change(AiCall, :count).by(1)
    end

    # A 200 with an HTML outage page is the provider failing, so the router
    # should move on to the next one.
    it "treats a non-JSON response body as the provider being unavailable" do
      response = instance_double(Net::HTTPResponse, code: "200", body: "<html>bad gateway</html>")
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(Net::HTTP).to receive(:start).and_return(response)

      expect {
        described_class.new.json_completion(purpose: :text_parse, messages: [], schema: {})
      }.to raise_error(described_class::Unavailable, /non-JSON/)
    end

    # Each of these is the provider, not the photo, so the router must move on.
    [ Errno::ECONNREFUSED, Errno::ECONNRESET, IO::TimeoutError, Net::OpenTimeout, Net::ReadTimeout,
      EOFError, SocketError, OpenSSL::SSL::SSLError ].each do |failure|
      it "turns #{failure} into Unavailable, not a raw socket error" do
        allow(Net::HTTP).to receive(:start).and_raise(failure)

        expect {
          described_class.new.json_completion(purpose: :text_parse, messages: [], schema: {})
        }.to raise_error(described_class::Unavailable, /transport/)
      end
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

    # The hint and the prompt only help if they actually reach the provider.
    it "sends the spoken language and the prompt as form fields" do
      sent = nil
      response = instance_double(Net::HTTPResponse, code: "200", body: { "text" => "Milch" }.to_json)
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      http = double("http")
      allow(http).to receive(:request) { |request| sent = request.body and response }
      allow(Net::HTTP).to receive(:start).and_yield(http)

      described_class.new(household: household).transcribe(
        io: StringIO.new("audio"), filename: "memo.mp4", content_type: "audio/mp4",
        language: "de", prompt: "Einkaufsliste: Milch, Brötchen."
      )

      expect(sent).to include(%(name="language"\r\n\r\nde\r\n))
      expect(sent.force_encoding(Encoding::UTF_8)).to include("Einkaufsliste: Milch, Brötchen.")
      expect(sent).to include(%(filename="memo.mp4"))
    end
  end
end
