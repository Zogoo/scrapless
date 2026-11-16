module Internal
  # The notification clock's doorbell. An hourly Fly machine POSTs here; the
  # request is what wakes this machine when it is asleep.
  #
  # Not a kitchen endpoint: no household, no cookie, no CORS, no body. It takes
  # no input and does one idempotent thing, so even a leaked token can only make
  # a tick happen early, and the Notification ledger still stops a second send.
  # Unknown callers get a 404, so the route does not announce itself.
  class NotificationsController < ActionController::API
    include ActionController::HttpAuthentication::Token::ControllerMethods

    # Short secrets are rejected outright rather than trusted.
    MIN_TOKEN_LENGTH = 32

    # Checked before the limit, so a stranger's failed guesses cannot use up
    # the clock's own allowance.
    before_action :verify_caller!
    rate_limit to: 10, within: 1.hour, with: -> { head :too_many_requests }

    def tick
      Notifications::DispatchJob.perform_later
      head :accepted
    end

    private

    # Fails closed: with no token configured, nothing gets in.
    def verify_caller!
      expected = ENV["NOTIFY_TICK_TOKEN"].to_s
      authorized = expected.length >= MIN_TOKEN_LENGTH && authenticate_with_http_token do |token, _|
        ActiveSupport::SecurityUtils.secure_compare(token, expected)
      end
      head :not_found unless authorized
    end
  end
end
