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
  end
end
