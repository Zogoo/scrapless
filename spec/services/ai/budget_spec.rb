require "rails_helper"

RSpec.describe Ai::Budget do
  around do |example|
    ENV["AI_DAILY_BUDGET_USD"] = "1.0"
    example.run
    ENV.delete("AI_DAILY_BUDGET_USD")
  end

  def spend(usd, at: Time.current)
    AiCall.create!(purpose: "receipt_extract", model: "gpt-5-mini", provider: "openai",
                   cost_micros: (usd * 1_000_000).round, created_at: at)
  end

  it "is not exceeded on a quiet day" do
    spend(0.10)
    expect(described_class).not_to be_exceeded
  end

  it "is exceeded once the day's calls add up to the ceiling" do
    spend(0.60)
    spend(0.45)
    expect(described_class).to be_exceeded
  end

  # A ceiling that resets itself on restart is not a ceiling, which is why this
  # counts the ledger rather than a cache counter.
  it "counts only today, so yesterday's spend does not block today" do
    spend(5.00, at: 2.days.ago)
    expect(described_class).not_to be_exceeded
  end

  it "can be switched off deliberately" do
    ENV["AI_DAILY_BUDGET_USD"] = "0"
    spend(50.0)
    expect(described_class).not_to be_exceeded
  end
end

RSpec.describe Ai::Router, "budget enforcement" do
  around do |example|
    ENV["AI_DAILY_BUDGET_USD"] = "0.01"
    ENV["OPENAI_API_KEY"] = "test-key"
    example.run
    %w[AI_DAILY_BUDGET_USD OPENAI_API_KEY].each { |k| ENV.delete(k) }
  end

  it "stops calling out once the day's budget is gone" do
    AiCall.create!(purpose: "receipt_extract", model: "gpt-5-mini", provider: "openai",
                   cost_micros: 20_000)
    expect(Net::HTTP).not_to receive(:start)

    expect { described_class.new.json_completion(purpose: :text_parse, messages: [], schema: {}) }
      .to raise_error(described_class::BudgetExceeded)
  end

  # It has to degrade the same way a provider outage does, or the ceiling turns
  # into a crash instead of a graceful "type it instead".
  it "reads as unavailable, so the free paths keep working" do
    AiCall.create!(purpose: "receipt_extract", model: "gpt-5-mini", provider: "openai",
                   cost_micros: 20_000)

    expect(described_class::BudgetExceeded.new).to be_a(Ai::Client::Unavailable)
  end
end
