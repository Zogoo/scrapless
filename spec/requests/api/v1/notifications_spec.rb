require "rails_helper"

RSpec.describe "Api::V1::Notifications", type: :request do
  let(:household) { create(:household) }
  let(:item) { create(:item, household: household, display_name: "Spinat") }

  it "lists the bell's notifications in the phone's language" do
    notification = create(:notification, household: household, item_ids: [ item.id ])

    get "/api/v1/notifications", headers: fridge_headers(household).merge("X-Locale" => "de")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to contain_exactly(
      include("id" => notification.id, "body" => "Spinat am besten heute Abend verbrauchen.",
              "url" => "/today?n=#{notification.id}", "unread" => true)
    )
  end

  it "marks one read for the whole kitchen, once" do
    notification = create(:notification, household: household)

    post "/api/v1/notifications/#{notification.id}/read", headers: fridge_headers(household)
    first = notification.reload.opened_at
    travel 1.hour do
      post "/api/v1/notifications/#{notification.id}/read", headers: fridge_headers(household)
    end

    expect(response).to have_http_status(:no_content)
    expect(notification.reload.opened_at).to eq(first)
  end

  # A phone still running the first push build after a deploy.
  it "still counts the old opened call" do
    notification = create(:notification, household: household)

    post "/api/v1/notifications/#{notification.id}/opened", headers: fridge_headers(household)

    expect(notification.reload.opened_at).to be_present
  end

  it "marks them all read, and only this kitchen's" do
    mine = [ 0, 1 ].map { |i| create(:notification, household: household, sent_on: Date.current - i, slot: i + 1) }
    theirs = create(:notification)

    post "/api/v1/notifications/read_all", headers: fridge_headers(household)

    expect(response).to have_http_status(:no_content)
    expect(mine.map { |n| n.reload.opened_at }).to all(be_present)
    expect(theirs.reload.opened_at).to be_nil
  end

  it "cannot touch another kitchen's notification" do
    theirs = create(:notification)

    post "/api/v1/notifications/#{theirs.id}/read", headers: fridge_headers(household)

    expect(response).to have_http_status(:not_found)
    expect(theirs.reload.opened_at).to be_nil
  end
end
