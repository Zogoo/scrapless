require "rails_helper"

RSpec.describe Ai::Router do
  let(:household) { create(:household) }

  around do |example|
    ENV["OPENAI_API_KEY"] = "openai-key"
    ENV["GEMINI_API_KEY"] = "gemini-key"
    ENV["AI_PROVIDERS"] = "openai,gemini"
    example.run
    %w[OPENAI_API_KEY GEMINI_API_KEY AI_PROVIDERS].each { |k| ENV.delete(k) }
  end

  # Stubs the transport per provider, keyed on the host it would call.
  def stub_transport(openai:, gemini:)
    allow(Net::HTTP).to receive(:start) do |host, *_args|
      host.to_s.include?("googleapis") ? gemini.call : openai.call
    end
  end

  def ok(content)
    response = instance_double(Net::HTTPResponse, code: "200", body: {
      "choices" => [ { "message" => { "content" => content } } ],
      "usage" => { "prompt_tokens" => 100, "completion_tokens" => 50 }
    }.to_json)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    response
  end

  def refused(code, body)
    response = instance_double(Net::HTTPResponse, code: code, body: body)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
    response
  end

  describe "#json_completion" do
    it "uses the primary provider when it is healthy" do
      stub_transport(openai: -> { ok('{"ok":true}') }, gemini: -> { raise "must not be called" })

      result = described_class.new(household: household)
                              .json_completion(purpose: :text_parse, messages: [], schema: {})

      expect(result).to eq("ok" => true)
      expect(AiCall.last).to have_attributes(provider: "openai", attempt: 0, success: true)
    end

    # The whole reason this class exists: a hard quota on the primary used to
    # take the entire capture path down until somebody topped up an account.
    it "falls back to the next provider when the primary is out of credit" do
      stub_transport(
        openai: -> { refused("429", '{"error":{"code":"credit_balance_exhausted"}}') },
        gemini: -> { ok('{"ok":"from gemini"}') }
      )

      result = described_class.new(household: household)
                              .json_completion(purpose: :text_parse, messages: [], schema: {})

      expect(result).to eq("ok" => "from gemini")
    end

    it "records both the failed attempt and the one that worked" do
      stub_transport(
        openai: -> { refused("429", "quota") },
        gemini: -> { ok('{"ok":true}') }
      )

      described_class.new(household: household)
                     .json_completion(purpose: :text_parse, messages: [], schema: {})

      expect(AiCall.order(:id).pluck(:provider, :attempt, :success))
        .to eq([ [ "openai", 0, false ], [ "gemini", 1, true ] ])
    end

    it "falls back on an outage and on a dead socket, not just on quota" do
      stub_transport(openai: -> { refused("503", "upstream down") }, gemini: -> { ok('{"ok":1}') })
      expect { described_class.new.json_completion(purpose: :text_parse, messages: [], schema: {}) }
        .not_to raise_error

      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)
      expect { described_class.new.json_completion(purpose: :text_parse, messages: [], schema: {}) }
        .to raise_error(Ai::Client::Unavailable)
    end

    # Paying a second provider to produce the same nonsense is just a second bill.
    it "does not fall back when the model answered and the answer was unusable" do
      stub_transport(openai: -> { ok("") }, gemini: -> { raise "must not be called" })

      expect { described_class.new.json_completion(purpose: :text_parse, messages: [], schema: {}) }
        .to raise_error(Ai::Client::Error, /empty completion/)
    end

    it "gives up with the last error when every provider refuses" do
      stub_transport(openai: -> { refused("429", "quota") }, gemini: -> { refused("429", "quota") })

      expect { described_class.new.json_completion(purpose: :text_parse, messages: [], schema: {}) }
        .to raise_error(Ai::Client::Unavailable)
      expect(AiCall.where(success: false).count).to eq(2)
    end
  end

  describe "#transcribe" do
    # Gemini's OpenAI-compatible layer has no audio endpoint at all, so it must
    # be skipped rather than tried and failed.
    it "skips providers that cannot transcribe instead of burning an attempt" do
      ENV["AI_PROVIDERS"] = "gemini,openai"
      stub_transport(
        openai: -> {
          response = instance_double(Net::HTTPResponse, code: "200", body: { "text" => "milch" }.to_json)
          allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          response
        },
        gemini: -> { raise "gemini has no transcription endpoint" }
      )

      text = described_class.new(household: household).transcribe(
        io: StringIO.new("audio"), filename: "a.webm", content_type: "audio/webm", duration_seconds: 10
      )

      expect(text).to eq("milch")
      expect(AiCall.where(purpose: "transcribe").pluck(:provider)).to eq([ "openai" ])
    end

    it "says so plainly when no provider in the chain can transcribe" do
      ENV["AI_PROVIDERS"] = "gemini"

      expect {
        described_class.new.transcribe(io: StringIO.new("a"), filename: "a.webm",
                                       content_type: "audio/webm")
      }.to raise_error(described_class::NoProviderAvailable)
    end

    # A failed upload has already consumed the stream; the next provider would
    # otherwise be handed zero bytes and "succeed" on silence.
    it "rewinds the audio before handing it to the next provider" do
      ENV["AI_PROVIDERS"] = "openai,groq"
      ENV["GROQ_API_KEY"] = "groq-key"
      io = StringIO.new("audio-bytes")
      seen = []

      allow(Net::HTTP).to receive(:start) do |host, *_args|
        request = nil
        seen << io.pos
        if host.to_s.include?("groq")
          request = instance_double(Net::HTTPResponse, code: "200", body: { "text" => "ok" }.to_json)
          allow(request).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        else
          request = instance_double(Net::HTTPResponse, code: "429", body: "quota")
          allow(request).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        end
        request
      end

      described_class.new.transcribe(io: io, filename: "a.webm", content_type: "audio/webm")

      expect(seen.size).to eq(2)
      expect(seen.last).to eq(seen.first), "the second provider was handed a consumed stream"
    ensure
      ENV.delete("GROQ_API_KEY")
    end
  end
end
