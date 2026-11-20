require "rails_helper"

RSpec.describe "Api::V1::Captures", type: :request do
  before do
    create(:shelf_life_rule, category: "produce", storage: "fridge",
                             days_p50: 5, days_p90: 9, consume_p50: 5)
    create(:shelf_life_rule, category: "dairy", storage: "fridge",
                             days_p50: 8, days_p90: 14, consume_p50: 6)
    create(:product_alias, raw_text: "milch", canonical_name: "Milch", category: "dairy")
  end

  let(:household) { create(:household) }
  let(:headers) { fridge_headers(household) }

  def receipt_upload
    Rack::Test::UploadedFile.new(StringIO.new("not-really-a-jpeg"), "image/jpeg",
                                 original_filename: "bon.jpg")
  end

  describe "POST /api/v1/captures" do
    it "turns a receipt photo into a reviewable list of items" do
      post "/api/v1/captures", params: { source: "receipt", image: receipt_upload }, headers: headers

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["capture"]["kind"]).to eq("receipt")
      expect(body["items"]).not_to be_empty
      expect(body["suppressed"]).to include("PFAND 0,25")
    end

    it "places each item on a photo of food, and none on a receipt" do
      post "/api/v1/captures", params: { source: "shelf_photo", image: receipt_upload }, headers: headers
      expect(response.parsed_body["items"].map { |i| i["box"] }).to all(include("x", "y", "w", "h"))

      post "/api/v1/captures", params: { source: "receipt", image: receipt_upload }, headers: headers
      expect(response.parsed_body["items"].map { |i| i["box"] }).to all(be_nil)
    end

    # The Kitchen shows "Milk" and "Milch" as one line (same product); the
    # review used to count by name and said there was only the new one.
    it "counts packs on the review the way the Kitchen groups them" do
      milk = Product.for("milk")
      ProductAlias.find_by(raw_text: "milch").update!(product: milk)
      create(:item, household: household, display_name: "Milk", canonical_name: "milk", category: "dairy",
                    storage: "fridge", product: milk)

      post "/api/v1/captures", params: { source: "text", text: "milch" }, headers: headers

      expect(response.parsed_body["items"].first["in_kitchen"]).to eq(2)
    end

    it "names a merged variety by its product on the review, and a plain item as itself" do
      allow(Ai::TextReader).to receive(:call).and_return("items" => [
        { "raw_text" => "basmatireis", "name" => "Basmatireis", "product" => "basmati rice",
          "quantity" => nil, "unit" => nil, "category" => "pantry", "storage" => "pantry" }
      ])

      post "/api/v1/captures", params: { source: "text", text: "basmatireis" },
                               headers: headers.merge("X-Locale" => "de")
      rice = response.parsed_body["items"].first
      expect(rice).to include("product_name" => "Reis", "merged" => true, "display_name" => include("Basmatireis"))

      post "/api/v1/captures", params: { source: "text", text: "milch" }, headers: headers.merge("X-Locale" => "de")
      expect(response.parsed_body["items"].first["merged"]).to be(false)
    end

    it "keeps the receipt image so a bad parse can be audited" do
      post "/api/v1/captures", params: { source: "receipt", image: receipt_upload }, headers: headers

      expect(Capture.last.image).to be_attached
    end

    # Voice goes through the dictionary before it reaches a model, so a sentence
    # made entirely of familiar words costs nothing at all.
    it "parses a spoken sentence of known words with no model call" do
      expect(Ai::TextReader).not_to receive(:call)

      post "/api/v1/captures", params: { source: "voice", transcript: "milch und milch" },
           headers: headers

      expect(response).to have_http_status(:created)
    end

    # The free path: the browser did the speech-to-text, so no audio is uploaded
    # and no transcription is billed.
    it "accepts a transcript the browser produced without touching the audio API" do
      expect {
        post "/api/v1/captures", params: { source: "voice", transcript: "milch und brokkoli" },
             headers: headers
      }.not_to change { AiCall.where(purpose: "transcribe").count }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["items"].map { |i| i["display_name"] }).to include(/Milch/)
    end

    it "asks for one thing on the manual path and accepts a whole sentence" do
      post "/api/v1/captures", params: { source: "text", text: "milch, brokkoli" }, headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["items"].size).to eq(2)
    end

    it "stamps the name on this phone onto the capture and each item" do
      post "/api/v1/captures", params: { source: "text", text: "milch" },
           headers: headers.merge("X-Actor-Name" => "Mama")

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["items"].first["added_by_name"]).to eq("Mama")
      expect(household.captures.last.added_by_name).to eq("Mama")
      expect(household.items.last.added_by_name).to eq("Mama")
    end

    it "says when a new pack joins one already in the kitchen" do
      post "/api/v1/captures", params: { source: "text", text: "milch" }, headers: headers
      expect(response.parsed_body["items"].first["in_kitchen"]).to eq(1)

      post "/api/v1/captures", params: { source: "text", text: "milch" }, headers: headers
      expect(response.parsed_body["items"].first["in_kitchen"]).to eq(2)
    end

    it "still captures when the phone has no name" do
      post "/api/v1/captures", params: { source: "text", text: "milch" }, headers: headers

      expect(response).to have_http_status(:created)
      expect(household.items.last.added_by_name).to be_nil
    end

    it "rejects an empty manual entry without creating a capture" do
      expect {
        post "/api/v1/captures", params: { source: "text", text: "" }, headers: headers
      }.not_to change(Capture, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    # There is no account wall in front of this endpoint and every call can cost
    # money, so the ceiling has to come from somewhere.
    it "stops a fridge uploading without limit" do
      described_class = Api::V1::CapturesController
      create_list(:capture, InputLimits::MAX_CAPTURES_PER_HOUR, household: household)

      post "/api/v1/captures", params: { source: "text", text: "milch" }, headers: headers

      expect(response).to have_http_status(:too_many_requests)
    end

    it "counts the budget out of the database, so a cache flush cannot reset it" do
      create_list(:capture, InputLimits::MAX_CAPTURES_PER_HOUR,
                  household: household, created_at: 2.hours.ago)

      post "/api/v1/captures", params: { source: "text", text: "milch" }, headers: headers

      expect(response).to have_http_status(:created)
    end

    # Observed against a real key with an empty balance: the provider returns 429
    # and every photo fails. Telling someone to retake it is a loop that cannot
    # terminate, so quota/auth/outage says something different from a bad photo.
    context "when the provider refuses the call" do
      before do
        allow(Ai::ImageReader).to receive(:call)
          .and_raise(Ai::Client::Unavailable, "429: insufficient_quota")
      end

      it "does not tell the user to retake a photo that can never work" do
        post "/api/v1/captures", params: { source: "receipt", image: receipt_upload },
             headers: headers

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body["retryable"]).to be(false)
        expect(response.parsed_body["error"]).to match(/type or say/i)
      end

      it "leaves the free paths working, because they never touch the provider" do
        post "/api/v1/captures", params: { source: "text", text: "milch" }, headers: headers

        expect(response).to have_http_status(:created)
        expect(response.parsed_body["items"].size).to eq(1)
      end

      # Observed live: "milch, brokkoli, yuzu kosho" lost all three, because one
      # unfamiliar word took the two free dictionary hits down with it.
      it "keeps the words the dictionary knew when the model cannot parse the rest" do
        allow(Ai::TextReader).to receive(:call)
          .and_raise(Ai::Client::Unavailable, "429: insufficient_quota")

        post "/api/v1/captures", params: { source: "text", text: "milch, yuzu kosho" },
             headers: headers

        expect(response).to have_http_status(:created)
        expect(response.parsed_body["items"].map { |i| i["display_name"] }).to include(/Milch/)
        expect(response.parsed_body["capture"]["notes"]).to include("yuzu kosho")
      end

      it "does the same for a spoken sentence" do
        allow(Ai::TextReader).to receive(:call)
          .and_raise(Ai::Client::Unavailable, "429: insufficient_quota")

        post "/api/v1/captures", params: { source: "voice", transcript: "milch und yuzu kosho" },
             headers: headers

        expect(response).to have_http_status(:created)
        expect(response.parsed_body["items"].size).to eq(1)
      end
    end

    it "still offers a retake when the model read the photo and made no sense of it" do
      allow(Ai::ImageReader).to receive(:call).and_raise(Ai::Client::Error, "empty completion")

      post "/api/v1/captures", params: { source: "receipt", image: receipt_upload },
           headers: headers

      expect(response.parsed_body["retryable"]).to be(true)
      expect(response.parsed_body["error"]).to match(/hard to read/i)
    end

    it "will not accept a capture without a fridge" do
      post "/api/v1/captures", params: { source: "text", text: "milch" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "input limits" do
    # In live mode every character of an unknown line goes to a paid model.
    it "refuses a typed shop longer than a shopping list" do
      post "/api/v1/captures", params: { source: "text", text: "milch, " * 200 }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(I18n.t("capture.rejected.too_long"))
    end

    it "refuses an endless spoken transcript too" do
      post "/api/v1/captures", params: { source: "voice", transcript: "brot " * 300 }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "answers in German when the phone asks for German" do
      post "/api/v1/captures", params: { source: "text", text: "" }, headers: headers.merge("X-Locale" => "de")

      expect(response.parsed_body["error"]).to eq("Schreib erst, was du gekauft hast.")
    end
  end
end
