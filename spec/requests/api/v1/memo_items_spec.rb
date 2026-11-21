require "rails_helper"

RSpec.describe "Api::V1::MemoItems", type: :request do
  let(:household) { create(:household) }
  let(:headers) { fridge_headers(household) }

  it "lists the memo with suggestions attached, so the list is never empty" do
    create(:memo_item, household: household, name: "Butter")

    get "/api/v1/memo", headers: headers
    body = response.parsed_body

    expect(body["items"].map { |i| i["name"] }).to eq([ "Butter" ])
    expect(body["suggestions"]).not_to be_empty
  end

  it "adds a line" do
    post "/api/v1/memo", params: { name: "Kaffee" }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(household.memo_items.pluck(:name)).to eq([ "Kaffee" ])
  end

  it "attributes a line to the name on the phone" do
    post "/api/v1/memo", params: { name: "Kaffee" },
         headers: headers.merge("X-Actor-Name" => "Mama"), as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["added_by_name"]).to eq("Mama")
    expect(household.memo_items.last.added_by_name).to eq("Mama")
  end

  it "leaves the name blank when the phone has not chosen one" do
    post "/api/v1/memo", params: { name: "Kaffee" }, headers: headers, as: :json

    expect(household.memo_items.last.added_by_name).to be_nil
  end

  it "attributes every line of a dictation to the same name" do
    post "/api/v1/memo/dictate", params: { transcript: "milk and bread" },
         headers: headers.merge("X-Actor-Name" => "Oma%20Inge"), as: :json

    expect(response).to have_http_status(:created)
    expect(household.memo_items.pluck(:added_by_name).uniq).to eq([ "Oma Inge" ])
  end

  it "keeps a very long name from failing the line" do
    post "/api/v1/memo", params: { name: "Kaffee", added_by: "M" * 80 }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(household.memo_items.last.added_by_name).to eq("M" * 40)
  end

  # The memo is the one place where cost per line should be exactly zero, so
  # dictation splits locally and never reaches a model.
  it "splits a spoken sentence into lines without calling a model" do
    expect {
      post "/api/v1/memo/dictate", params: { transcript: "milk, bread and coffee" },
           headers: headers, as: :json
    }.not_to change(AiCall, :count)

    expect(response).to have_http_status(:created)
    expect(household.memo_items.pluck(:name)).to eq(%w[Milk Bread Coffee])
  end

  # Browser recognisers return no commas (doc 15 §15.2.3).
  it "splits a sentence with no punctuation, in either language" do
    post "/api/v1/memo/dictate", params: { transcript: "I want to buy bread milk eggs" }, headers: headers, as: :json
    post "/api/v1/memo/dictate", params: { transcript: "ich brauche Brot Milch und Eier" }, headers: headers, as: :json

    expect(household.memo_items.order(:id).pluck(:name)).to eq(%w[Bread Milk Eggs Brot Milch Eier])
  end

  # Hold-to-talk sends one item at a time.
  it "adds a single held word as one line" do
    post "/api/v1/memo/dictate", params: { transcript: "Klopapier" }, headers: headers, as: :json

    expect(response.parsed_body["items"].map { |i| i["name"] }).to eq([ "Klopapier" ])
  end

  it "rejects a transcript too long to be a shopping list" do
    post "/api/v1/memo/dictate", params: { transcript: "milch " * 300 }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(household.memo_items).to be_empty
  end

  # A correction is how a kitchen teaches the mic its own words.
  it "learns from renaming a line the mic wrote" do
    # Unknown words with no item after them are a line of their own.
    post "/api/v1/memo/dictate", params: { transcript: "Milch ich hätt gern" }, headers: headers, as: :json
    line = household.memo_items.find_by!(canonical_name: "ich hätt gern")

    patch "/api/v1/memo/#{line.id}", params: { memo_item: { name: "Hafermilch" } }, headers: headers, as: :json
    post "/api/v1/memo/dictate", params: { transcript: "hafermilch brot" }, headers: headers, as: :json

    expect(household.vocabulary_entries.pluck(:kind, :phrase)).to include([ "item", "hafermilch" ])
    expect(response.parsed_body["items"].map { |i| i["name"] }).to eq([ "Brot" ])
  end

  it "records how the mic was used, so the gestures are measured" do
    allow(Rails.logger).to receive(:info).and_call_original

    post "/api/v1/memo/dictate", params: { transcript: "Milch", lang: "de", gesture: "hold", press_ms: 820 },
                                 headers: headers, as: :json

    expect(Rails.logger).to have_received(:info).with(/gesture=hold press_ms=820 lang=de/)
  end

  # Which path read each dictation, and how long a model took, is how the
  # model timeout and the cost are tuned (doc 15 §15.11).
  it "records which path read the sentence, without what was said" do
    allow(Rails.logger).to receive(:info).and_call_original

    post "/api/v1/memo/dictate", params: { transcript: "peanut butter", lang: "en" }, headers: headers, as: :json

    expect(Rails.logger).to have_received(:info).with(/path=segmenter reason=ai_off model_ms=0/)
    expect(Rails.logger).not_to have_received(:info).with(/memo dictation .*peanut/)
  end

  # Self-corrections and filler the lexicon does not know: the case a model is for.
  it "adds the model's lines when the segmenter is unsure and AI is live" do
    allow(Ai::Config).to receive(:live?).and_return(true)
    router = instance_double(Ai::Router, json_completion: { "items" => [
      { "name" => "Hafermilch", "quantity" => nil, "unit" => nil, "food" => true },
      { "name" => "Brot", "quantity" => nil, "unit" => nil, "food" => true }
    ] })
    allow(Ai::Router).to receive(:new).and_return(router)

    post "/api/v1/memo/dictate", params: { transcript: "Milch nee warte Hafermilch und Brot", lang: "de" },
                                 headers: headers, as: :json

    expect(response.parsed_body["items"].map { |i| i["name"] }).to eq(%w[Hafermilch Brot])
  end

  it "keeps an unknown gesture value out of the log" do
    allow(Rails.logger).to receive(:info).and_call_original

    post "/api/v1/memo/dictate", params: { transcript: "Milch", gesture: "hold\nforged=1" }, headers: headers, as: :json

    expect(Rails.logger).to have_received(:info).with(/gesture=unknown /)
  end

  describe "sections and quantities" do
    it "files a line under its store section and reads a count off the front" do
      post "/api/v1/memo", params: { name: "2 Gurken" }, headers: headers, as: :json

      expect(response.parsed_body).to include("name" => "Gurken", "quantity" => 2,
                                              "category" => Categories.guess("Gurken"))
    end

    it "keeps a second add without a number as the one line, unchanged" do
      create(:memo_item, household: household, name: "Milch", quantity: 2)

      post "/api/v1/memo", params: { name: "Milch" }, headers: headers, as: :json

      expect(response.parsed_body).to include("quantity" => 2, "merged" => true)
      expect(household.memo_items.count).to eq(1)
    end

    it "adds a counted second add to the line that is there" do
      create(:memo_item, household: household, name: "Äpfel", quantity: 2)

      post "/api/v1/memo", params: { name: "1 Äpfel" }, headers: headers, as: :json
      expect(response.parsed_body).to include("quantity" => 3, "merged" => true)

      post "/api/v1/memo", params: { name: "Äpfel", quantity: 2 }, headers: headers, as: :json
      expect(response.parsed_body["quantity"]).to eq(5)
      expect(household.memo_items.count).to eq(1)
    end

    it "keeps the quantities a model read off a sentence, and a measure in the name" do
      reading = Memo::ListReader::Result.new(lines: [ "2 Gurken", "500 g Mehl" ], path: "model", reason: "unsure",
                                             model_ms: 10, unresolved: [])
      allow(Memo::ListReader).to receive(:call).and_return(reading)

      post "/api/v1/memo/dictate", params: { transcript: "zwei Gurken und 500 Gramm Mehl" }, headers: headers,
                                   as: :json

      expect(household.memo_items.order(:id).pluck(:name, :quantity)).to eq([ [ "Gurken", 2 ], [ "500 g Mehl", 1 ] ])
    end

    it "sums a dictated count into a line that is already open" do
      create(:memo_item, household: household, name: "Gurken", quantity: 1)
      reading = Memo::ListReader::Result.new(lines: [ "2 Gurken" ], path: "model", reason: "unsure",
                                             model_ms: 10, unresolved: [])
      allow(Memo::ListReader).to receive(:call).and_return(reading)

      post "/api/v1/memo/dictate", params: { transcript: "zwei Gurken" }, headers: headers, as: :json

      expect(household.memo_items.sole.quantity).to eq(3)
    end

    it "lets a quantity be changed, between 1 and 99" do
      line = create(:memo_item, household: household, name: "Eier")

      patch "/api/v1/memo/#{line.id}", params: { memo_item: { quantity: 6 } }, headers: headers, as: :json
      expect(line.reload.quantity).to eq(6)

      patch "/api/v1/memo/#{line.id}", params: { memo_item: { quantity: 100 } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "recorded audio" do
    def audio = Rack::Test::UploadedFile.new(StringIO.new("not-really-audio"), "audio/mp4", original_filename: "memo.mp4")

    # The language spoken is not always the app's: an English screen in a
    # German supermarket.
    it "transcribes in the language the person chose to speak" do
      allow(Ai::Transcriber).to receive(:call).and_return("Milch")

      post "/api/v1/memo/dictate", params: { audio: audio, lang: "de", duration_seconds: 2 },
                                   headers: headers.merge("X-Locale" => "en")

      expect(Ai::Transcriber).to have_received(:call).with(hash_including(language: "de", content_type: "audio/mp4"))
      expect(household.memo_items.pluck(:name)).to eq([ "Milch" ])
    end

    it "falls back to the app's language when none is sent" do
      allow(Ai::Transcriber).to receive(:call).and_return("milk")

      post "/api/v1/memo/dictate", params: { audio: audio }, headers: headers.merge("X-Locale" => "en")

      expect(Ai::Transcriber).to have_received(:call).with(hash_including(language: "en"))
    end

    it "stops paying for transcriptions after the hourly cap" do
      InputLimits::MAX_TRANSCRIPTIONS_PER_HOUR.times do
        AiCall.create!(household: household, purpose: "transcribe", model: "gpt-4o-mini-transcribe")
      end
      allow(Ai::Transcriber).to receive(:call)

      post "/api/v1/memo/dictate", params: { audio: audio }, headers: headers

      expect(response).to have_http_status(:too_many_requests)
      expect(Ai::Transcriber).not_to have_received(:call)
    end
  end

  it "ticks a line off" do
    memo = create(:memo_item, household: household)

    patch "/api/v1/memo/#{memo.id}", params: { memo_item: { done: true } },
          headers: headers, as: :json

    expect(memo.reload.done).to be(true)
    expect(memo.done_at).to be_present
  end

  describe "GET /api/v1/memo/suggestions" do
    it "autosuggests as the user types" do
      get "/api/v1/memo/suggestions", params: { q: "cof" }, headers: headers

      expect(response.parsed_body.map { |s| s["name"] }).to eq([ "Coffee" ])
    end

    it "ranks what this household actually buys above the generic staples" do
      [ 21, 14, 7 ].each do |days_ago|
        create(:item, household: household, canonical_name: "hafermilch", display_name: "Hafermilch",
                      acquired_on: Date.current - days_ago)
      end

      get "/api/v1/memo/suggestions", headers: headers

      expect(response.parsed_body.first["name"]).to eq("Hafermilch")
    end
  end

  describe "QA fixes" do
    # Two phones adding the same thing to one shared list.
    it "keeps one open line per name" do
      post "/api/v1/memo", params: { name: "gouda" }, headers: headers
      post "/api/v1/memo", params: { name: "Gouda" }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(household.memo_items.pluck(:name)).to eq([ "Gouda" ])
    end

    it "does not add a spoken line that is already open" do
      create(:memo_item, household: household, name: "Milch")

      post "/api/v1/memo/dictate", params: { transcript: "milch und brot" }, headers: headers

      expect(household.memo_items.order(:id).pluck(:name)).to eq(%w[Milch Brot])
    end

    it "clears every bought line in one go, and only those" do
      create(:memo_item, household: household, name: "Eier", done: true)
      create(:memo_item, household: household, name: "Brot")

      delete "/api/v1/memo/clear_done", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(household.memo_items.pluck(:name)).to eq([ "Brot" ])
    end

    it "stops suggesting a dismissed name" do
      create(:item, household: household, canonical_name: "thing17", display_name: "Thing17",
                    state: "rescued")

      post "/api/v1/memo/dismiss_suggestion", params: { name: "Thing17" }, headers: headers

      expect(response.parsed_body.map { |s| s["name"] }).not_to include("Thing17")
    end
  end
end
