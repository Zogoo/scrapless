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

    it "keeps the receipt image so a bad parse can be audited" do
      post "/api/v1/captures", params: { source: "receipt", image: receipt_upload }, headers: headers

      expect(Capture.last.image).to be_attached
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
      create_list(:capture, described_class::MAX_CAPTURES_PER_HOUR, household: household)

      post "/api/v1/captures", params: { source: "text", text: "milch" }, headers: headers

      expect(response).to have_http_status(:too_many_requests)
    end

    it "counts the budget out of the database, so a cache flush cannot reset it" do
      create_list(:capture, Api::V1::CapturesController::MAX_CAPTURES_PER_HOUR,
                  household: household, created_at: 2.hours.ago)

      post "/api/v1/captures", params: { source: "text", text: "milch" }, headers: headers

      expect(response).to have_http_status(:created)
    end

    it "will not accept a capture without a fridge" do
      post "/api/v1/captures", params: { source: "text", text: "milch" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
