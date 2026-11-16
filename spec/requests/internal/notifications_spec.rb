require "rails_helper"

RSpec.describe "Internal::Notifications", type: :request do
  let(:token) { SecureRandom.hex(32) }

  def tick(with: token)
    post "/internal/notifications/tick", headers: { "Authorization" => "Bearer #{with}" }
  end

  it "starts a dispatch for the hourly clock" do
    with_env("NOTIFY_TICK_TOKEN" => token) do
      expect { tick }.to have_enqueued_job(Notifications::DispatchJob)
    end

    expect(response).to have_http_status(:accepted)
  end

  it "does not announce itself to a wrong token" do
    with_env("NOTIFY_TICK_TOKEN" => token) do
      expect { tick(with: "#{token}x") }.not_to have_enqueued_job
    end

    expect(response).to have_http_status(:not_found)
  end

  it "does not accept a kitchen's own bearer token" do
    with_env("NOTIFY_TICK_TOKEN" => token) { tick(with: create(:household).token) }

    expect(response).to have_http_status(:not_found)
  end

  # The classic mistake: an unset secret compared with an empty header.
  it "fails closed when no token is configured" do
    with_env("NOTIFY_TICK_TOKEN" => nil) do
      post "/internal/notifications/tick", headers: { "Authorization" => "Bearer " }
      expect(response).to have_http_status(:not_found)
      tick(with: "")
      expect(response).to have_http_status(:not_found)
    end
  end

  it "refuses a configured token that is too short to trust" do
    with_env("NOTIFY_TICK_TOKEN" => "short") { tick(with: "short") }

    expect(response).to have_http_status(:not_found)
  end

  it "is not reachable with GET" do
    with_env("NOTIFY_TICK_TOKEN" => token) do
      get "/internal/notifications/tick", headers: { "Authorization" => "Bearer #{token}" }
    end

    expect(response).not_to have_http_status(:accepted)
  end
end
