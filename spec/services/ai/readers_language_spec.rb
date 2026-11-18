require "rails_helper"

# Whatever language the receipt, packet or sentence is in, names come back in
# the language the person's app is set to.
RSpec.describe "AI readers answer in the person's language" do
  let(:household) { create(:household) }
  let(:router) { instance_double(Ai::Router, json_completion: { "lines" => [], "items" => [] }) }

  around do |example|
    ENV["AI_MODE"] = "live"
    ENV["OPENAI_API_KEY"] = "test-key"
    example.run
  ensure
    ENV["AI_MODE"] = "stub"
    ENV.delete("OPENAI_API_KEY")
  end

  before { allow(Ai::Router).to receive(:new).and_return(router) }

  def system_prompt
    prompt = nil
    expect(router).to have_received(:json_completion) { |messages:, **| prompt = messages.first[:content] }
    prompt
  end

  it "asks the photo reader for German names in a German app" do
    I18n.with_locale(:de) do
      Ai::ImageReader.call(image_data: "x", content_type: "image/jpeg", household: household)
    end

    expect(system_prompt).to include("written in German")
  end

  # Without a meaning for each name the model guessed: milk was a drink.
  it "tells the photo reader what every category holds" do
    Ai::ImageReader.call(image_data: "x", content_type: "image/jpeg", household: household)

    expect(system_prompt).to include(*Categories::GUIDE.map { |name, holds| "#{name}: #{holds}" })
  end

  it "asks the text reader for English names in an English app" do
    I18n.with_locale(:en) { Ai::TextReader.call(text: "milch und brot", household: household) }

    expect(system_prompt).to include("written in English")
  end

  # The labels are what lets Captures::Ingest drop a till's detail rows.
  it "makes the photo reader say what every row is, and where the food goes" do
    Ai::ImageReader.call(image_data: "x", content_type: "image/jpeg", household: household)

    expect(router).to have_received(:json_completion) do |schema:, **|
      line = schema[:properties][:lines][:items]
      expect(line[:required]).to include("row", "category", "storage")
      expect(line[:properties][:row][:enum]).to eq(Ai::ImageReader::ROWS)
      expect(line[:properties][:category][:enum]).to eq(Categories::NAMES)
    end
  end
end
