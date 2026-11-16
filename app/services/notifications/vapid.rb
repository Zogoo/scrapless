module Notifications
  # The server's Web Push identity (RFC 8292). Both keys are Fly secrets; without
  # them the feature is off: the client is told there is no key and offers
  # nothing, and Dispatch sends nothing.
  module Vapid
    module_function

    def public_key = ENV["VAPID_PUBLIC_KEY"].presence

    def configured? = public_key.present? && ENV["VAPID_PRIVATE_KEY"].present?

    def details
      { subject: subject, public_key: public_key, private_key: ENV.fetch("VAPID_PRIVATE_KEY") }
    end

    # Push services want a mailto: or https: contact. The app's own address is
    # one, and it avoids putting a person's email in every request.
    def subject
      ENV["VAPID_SUBJECT"].presence ||
        ENV["APP_FRONTEND_URL"].to_s.then { |url| url.start_with?("https://") ? url : "https://scrapless-app.fly.dev" }
    end
  end
end
