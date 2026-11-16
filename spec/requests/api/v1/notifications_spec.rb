require "rails_helper"

RSpec.describe "Api::V1::Notifications", type: :request do
  let(:household) { create(:household) }

  it "counts a notification as opened, once" do
    notification = create(:notification, household: household)

    post "/api/v1/notifications/#{notification.id}/opened", headers: fridge_headers(household)
    first = notification.reload.opened_at
    travel 1.hour do
      post "/api/v1/notifications/#{notification.id}/opened", headers: fridge_headers(household)
    end

    expect(response).to have_http_status(:no_content)
    expect(notification.reload.opened_at).to eq(first)
  end

  it "cannot touch another kitchen's notification" do
    theirs = create(:notification)

    post "/api/v1/notifications/#{theirs.id}/opened", headers: fridge_headers(household)

    expect(response).to have_http_status(:not_found)
    expect(theirs.reload.opened_at).to be_nil
  end
end
