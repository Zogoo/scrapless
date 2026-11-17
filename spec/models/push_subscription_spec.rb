require "rails_helper"

RSpec.describe PushSubscription do
  let(:household) { create(:household) }

  def subscription(endpoint)
    build(:push_subscription, household: household, endpoint: endpoint)
  end

  it "accepts the push services the browsers hand out" do
    [
      "https://fcm.googleapis.com/fcm/send/abc",
      "https://updates.push.services.mozilla.com/wpush/v2/abc",
      "https://web.push.apple.com/QGuQyavXutnMH",
      "https://wns2-db5p.notify.windows.com/w/?token=abc"
    ].each { |endpoint| expect(subscription(endpoint)).to be_valid, endpoint }
  end

  # The server POSTs to whatever is stored here, so anything else would let a
  # client aim our server at an address of its choosing (SSRF).
  it "refuses anything that is not a push service over https" do
    [
      "http://fcm.googleapis.com/fcm/send/abc",
      "https://169.254.169.254/latest/meta-data",
      "https://localhost:3000/internal/notifications/tick",
      "https://fcm.googleapis.com.evil.example/abc",
      "https://evilnotify.windows.com/abc",
      "https://user:pass@fcm.googleapis.com/abc",
      "https://fcm.googleapis.com:8443/abc",
      "not a url at all"
    ].each { |endpoint| expect(subscription(endpoint)).not_to be_valid, endpoint }
  end

  it "refuses keys that are not base64url" do
    expect(build(:push_subscription, household: household, auth: "<script>")).not_to be_valid
  end

  it "moves a phone to the kitchen it registers from, instead of adding it twice" do
    other = create(:household)
    first = create(:push_subscription, household: household)

    moved = described_class.register!(household: other, endpoint: first.endpoint,
                                      p256dh: first.p256dh, auth: first.auth, locale: "de")

    expect(moved.id).to eq(first.id)
    expect(moved.reload).to have_attributes(household_id: other.id, locale: "de")
    expect(described_class.count).to eq(1)
  end

  it "caps the phones per kitchen" do
    create_list(:push_subscription, described_class::MAX_PER_HOUSEHOLD, household: household)

    expect(build(:push_subscription, household: household)).not_to be_valid
  end
end
