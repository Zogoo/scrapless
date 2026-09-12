require "rails_helper"

RSpec.describe Ai::Config do
  describe ".cost_micros" do
    # The figure doc 12 quotes for a 30-line German Bon on the mini tier. If this
    # drifts, the unit-economics case in docs/13-mvp-cost-model.md drifts with it.
    it "prices a receipt read at roughly a quarter of a cent" do
      micros = described_class.cost_micros("gpt-5-mini", 2500, 900)

      expect(micros / 1_000_000.0).to be_within(0.0005).of(0.0024)
    end

    it "prices the text tier an order of magnitude below the vision tier" do
      vision = described_class.cost_micros("gpt-5-mini", 1000, 500)
      text = described_class.cost_micros("gpt-5-nano", 1000, 500)

      expect(text).to be < vision / 4
    end

    it "returns zero rather than raising for a model it has no price for" do
      expect(described_class.cost_micros("some-future-model", 1000, 500)).to eq(0)
    end
  end

  describe ".model_for" do
    it "sends receipts to the vision tier and text to the cheap tier" do
      expect(described_class.model_for(:receipt_extract).name).to eq("gpt-5-mini")
      expect(described_class.model_for(:text_parse).name).to eq("gpt-5-nano")
    end

    # An unpriced model would silently under-report cost, which is the one thing
    # this table exists to prevent.
    it "refuses a model that has no price attached" do
      ENV["AI_MODEL_RECEIPT_EXTRACT"] = "mystery-model"

      expect { described_class.model_for(:receipt_extract) }
        .to raise_error(ArgumentError, /unknown model/)
    ensure
      ENV.delete("AI_MODEL_RECEIPT_EXTRACT")
    end
  end

  describe ".mode" do
    it "runs against the stub when no key is configured, so the app still works" do
      expect(described_class.mode).to eq("stub")
    end

    # rails_helper pins AI_MODE=stub for the whole suite, so the example above
    # never actually exercises detection. This one does — and it has to clear the
    # provider keys itself, because dotenv loads a developer's real .env into the
    # test process. (That it does is exactly why the AI_MODE guard exists.)
    it "detects live mode from a key rather than from AI_MODE alone" do
      saved = described_class::PROVIDERS.values.to_h { |p| [ p.key_env, ENV[p.key_env] ] }
      saved.each_key { |k| ENV.delete(k) }
      ENV.delete("AI_MODE")

      expect(described_class.mode).to eq("stub")

      ENV["GEMINI_API_KEY"] = "test-key"
      expect(described_class.mode).to eq("live")
    ensure
      ENV["AI_MODE"] = "stub"
      saved&.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end

  describe ".chain" do
    it "is every provider with a key, primary first" do
      saved = described_class::PROVIDERS.values.to_h { |p| [ p.key_env, ENV[p.key_env] ] }
      saved.each_key { |k| ENV.delete(k) }
      ENV["OPENAI_API_KEY"] = "a"
      ENV["GEMINI_API_KEY"] = "b"

      expect(described_class.chain.map(&:name)).to eq(%w[openai gemini])
    ensure
      saved&.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    it "honours an explicit order" do
      ENV["AI_PROVIDERS"] = "gemini,openai"

      expect(described_class.chain.map(&:name)).to eq(%w[gemini openai])
    ensure
      ENV.delete("AI_PROVIDERS")
    end

    # Local has no credential to detect, so auto-detecting it would put it in
    # every chain and make a keyless install think it was live.
    it "never auto-detects the local runner" do
      expect(described_class.chain.map(&:name)).not_to include("local")
    end

    it "still allows the local runner when it is asked for explicitly" do
      ENV["AI_PROVIDERS"] = "local"

      expect(described_class.chain.map(&:name)).to eq([ "local" ])
      expect(described_class.api_key(provider: described_class::PROVIDERS["local"])).to be_present
    ensure
      ENV.delete("AI_PROVIDERS")
    end

    it "picks a per-provider model, so each provider gets one it actually has" do
      openai = described_class::PROVIDERS.fetch("openai")
      gemini = described_class::PROVIDERS.fetch("gemini")

      expect(described_class.model_for(:receipt_extract, provider: openai).name).to eq("gpt-5-mini")
      expect(described_class.model_for(:receipt_extract, provider: gemini).name).to eq("gemini-2.5-flash")
    end
  end
end
