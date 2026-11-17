require "rails_helper"

RSpec.describe "Api::V1::PushSubscriptions", type: :request do
  let(:household) { create(:household) }
  # The shape the browser's PushSubscription#toJSON() produces.
  let(:body) do
    { endpoint: "https://fcm.googleapis.com/fcm/send/abc", expirationTime: nil,
      keys: { p256dh: attributes_for(:push_subscription)[:p256dh], auth: "tBHItJI5svbpez7KI4CCXg" } }
  end

  around { |example| with_env(vapid_env) { example.run } }

  it "hands out the public key, and nothing else" do
    get "/api/v1/push_subscription/key", headers: fridge_headers(household)

    expect(response.parsed_body).to eq("public_key" => "BPublicKeyForSpecs")
  end

  it "says there is no key when the server has none, so the phone offers nothing" do
    with_env("VAPID_PUBLIC_KEY" => nil) do
      get "/api/v1/push_subscription/key", headers: fridge_headers(household)
    end

    expect(response.parsed_body["public_key"]).to be_nil
  end

  it "subscribes this phone to this kitchen, in its language" do
    post "/api/v1/push_subscription", params: body, as: :json,
                                      headers: fridge_headers(household).merge("X-Locale" => "de")

    expect(response).to have_http_status(:created)
    expect(household.push_subscriptions.sole).to have_attributes(endpoint: body[:endpoint], locale: "de")
  end

  it "refuses an endpoint that is not a push service" do
    post "/api/v1/push_subscription", params: body.merge(endpoint: "https://169.254.169.254/x"),
                                      as: :json, headers: fridge_headers(household)

    expect(response).to have_http_status(:unprocessable_content)
    expect(PushSubscription.count).to eq(0)
  end

  it "needs a kitchen" do
    post "/api/v1/push_subscription", params: body, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it "unsubscribes only this kitchen's phone" do
    mine = create(:push_subscription, household: household)
    theirs = create(:push_subscription)

    delete "/api/v1/push_subscription", params: { endpoint: theirs.endpoint }, as: :json,
                                        headers: fridge_headers(household)
    expect(PushSubscription.exists?(theirs.id)).to be(true)

    delete "/api/v1/push_subscription", params: { endpoint: mine.endpoint }, as: :json,
                                        headers: fridge_headers(household)
    expect(response).to have_http_status(:no_content)
    expect(PushSubscription.exists?(mine.id)).to be(false)
  end
end
