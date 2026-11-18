require "rails_helper"

RSpec.describe Memo::ListReader do
  let(:household) { create(:household) }
  let(:router) { instance_double(Ai::Router) }

  before do
    Rails.application.load_seed
    Text::Lexicon.reset!
    allow(Ai::Router).to receive(:new).and_return(router)
  end

  def read(text, lang: "de") = described_class.call(text: text, household: household, lang: lang)

  def model_says(*items)
    allow(router).to receive(:json_completion).and_return(
      "items" => items.map { |name, quantity, unit| { "name" => name, "quantity" => quantity, "unit" => unit, "food" => true } }
    )
  end

  context "when the segmenter knows every word" do
    it "uses its lines and never calls a model, even with AI live" do
      allow(Ai::Config).to receive(:live?).and_return(true)
      allow(router).to receive(:json_completion)

      result = read("ich brauche Brot Milch und zwei Zwiebeln")

      expect(result).to have_attributes(lines: [ "Brot", "Milch", "2 Zwiebeln" ], path: "segmenter", reason: "sure")
      expect(router).not_to have_received(:json_completion)
    end
  end

  context "when a word is left over" do
    let(:said) { "ähm also ich brauch noch Milch nee warte Hafermilch und Brot" }

    before { allow(Ai::Config).to receive(:live?).and_return(true) }

    it "asks the model, within the time a person waits, and uses its lines" do
      model_says([ "Hafermilch" ], [ "Brot" ])

      result = read(said)

      expect(result).to have_attributes(lines: %w[Hafermilch Brot], path: "model", reason: "unsure")
      expect(router).to have_received(:json_completion)
        .with(hash_including(purpose: :memo_parse, timeout: described_class::TIMEOUT))
    end

    it "sends the prompt the eval measures, and the sentence as said" do
      model_says([ "Brot" ])

      read(said)

      expect(router).to have_received(:json_completion) do |args|
        expect(args[:schema]).to eq(Memo::ListPrompt::SCHEMA)
        expect(args[:messages]).to eq([ { role: "system", content: Memo::ListPrompt::SYSTEM },
                                        { role: "user", content: said } ])
      end
    end

    it "writes amounts and units the way the segmenter does" do
      allow(router).to receive(:json_completion).and_return("items" => [
        { "name" => "Kartoffeln", "quantity" => 2, "unit" => "Kilo", "food" => true },
        { "name" => "Hackfleisch", "quantity" => 0.5, "unit" => "Kilo", "food" => true },
        { "name" => "Spaghetti", "quantity" => nil, "unit" => nil, "food" => true }
      ])

      expect(read("zwei Kilo Kartoffeln ein halbes Kilo Hackfleisch und Spaghetti für den Kuchen", lang: "en").lines)
        .to eq([ "2 Kilo Kartoffeln", "0.5 Kilo Hackfleisch", "Spaghetti" ])
    end

    it "adds nothing when the model finds nothing to buy" do
      model_says

      expect(read("nothing never mind")).to have_attributes(lines: [], path: "model")
    end

    # The model may only choose among the words said.
    it "keeps the segmenter's lines when the model names a word nobody said" do
      model_says([ "Hafermilch" ], [ "Brot" ], [ "Butter" ])

      expect(read(said)).to have_attributes(path: "fallback", reason: "ungrounded",
                                            lines: Text::Segmenter.call(text: said, household: household).parts)
    end

    {
      Ai::Router::DeadlinePassed.new("late") => "timeout",
      Ai::Client::TimedOut.new("transport: Net::ReadTimeout") => "timeout",
      Ai::Router::BudgetExceeded.new("spent") => "budget",
      Ai::Client::Unavailable.new("503") => "unavailable",
      Ai::Client::Error.new("unparseable completion") => "invalid"
    }.each do |error, reason|
      it "keeps the segmenter's lines, as said, when the model fails with #{error.class.name.demodulize}" do
        allow(router).to receive(:json_completion).and_raise(error)

        result = read(said)

        expect(result).to have_attributes(path: "fallback", reason: reason)
        expect(result.lines).to eq(Text::Segmenter.call(text: said, household: household).parts)
        expect(result.lines.join(" ")).to include("Hafermilch", "Brot")
      end
    end
  end

  it "uses the segmenter alone, and says so, when AI is off" do
    allow(router).to receive(:json_completion)

    result = read("peanut butter")

    expect(result).to have_attributes(path: "segmenter", reason: "ai_off")
    expect(router).not_to have_received(:json_completion)
  end
end
