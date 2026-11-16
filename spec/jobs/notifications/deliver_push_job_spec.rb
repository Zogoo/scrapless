require "rails_helper"

RSpec.describe Notifications::DeliverPushJob do
  include ActiveJob::TestHelper

  let(:household) { create(:household) }
  let(:subscription) { create(:push_subscription, household: household, locale: "en") }
  let(:item) { create(:item, household: household, display_name: "Spinat") }
  let(:notification) { create(:notification, household: household, item_ids: [ item.id ]) }

  around { |example| with_env(vapid_env) { example.run } }

  before { travel_to Time.utc(2026, 11, 18, 17, 30) }

  def perform = described_class.perform_now(notification.id, subscription.id)

  def push_error(klass, code)
    klass.new(instance_double(Net::HTTPResponse, code: code.to_s, body: ""), "fcm.googleapis.com")
  end

  it "sends the message to the phone and remembers that it worked" do
    allow(WebPush).to receive(:payload_send)

    perform

    expect(WebPush).to have_received(:payload_send).with(
      hash_including(endpoint: subscription.endpoint, ttl: 3.hours.to_i,
                     message: include("Spinat wants using tonight."))
    )
    expect(subscription.reload.last_delivered_at).to be_present
  end

  it "forgets a phone that unsubscribed" do
    allow(WebPush).to receive(:payload_send).and_raise(push_error(WebPush::ExpiredSubscription, 410))

    perform

    expect(PushSubscription.exists?(subscription.id)).to be(false)
  end

  it "retries when the push service is down" do
    allow(WebPush).to receive(:payload_send).and_raise(push_error(WebPush::PushServiceError, 503))

    expect { perform }.to have_enqueued_job(described_class).with(notification.id, subscription.id)
    expect(PushSubscription.exists?(subscription.id)).to be(true)
  end

  # A key mismatch is our fault, not the phone's; deleting would wipe everyone.
  it "keeps the phone when the server's own key is refused" do
    allow(WebPush).to receive(:payload_send).and_raise(push_error(WebPush::Unauthorized, 403))

    expect { perform }.to raise_error(WebPush::Unauthorized)
    expect(PushSubscription.exists?(subscription.id)).to be(true)
  end

  it "does not send yesterday's evening" do
    allow(WebPush).to receive(:payload_send)
    notification.update!(sent_on: Date.yesterday, iso_week: Notification.week_of(Date.yesterday))

    perform

    expect(WebPush).not_to have_received(:payload_send)
  end

  it "does not tell a phone about a kitchen it has left" do
    allow(WebPush).to receive(:payload_send)
    subscription.update!(household: create(:household))

    perform

    expect(WebPush).not_to have_received(:payload_send)
  end
end
