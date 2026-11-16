module Api
  module V1
    # This phone's yes (or no) to notifications.
    class PushSubscriptionsController < ApplicationController
      rate_limit to: 30, within: 1.hour, only: :create, name: "subscribe",
                 with: -> { render json: { error: I18n.t("notifications.too_many") }, status: :too_many_requests }

      # The VAPID public key the browser subscribes with. Null when the server has
      # no keys, and the client then offers nothing.
      def key
        render json: { public_key: Notifications::Vapid.public_key }
      end

      # The body is the browser's own PushSubscription#toJSON(). Registering the
      # same endpoint again is how a phone that switched kitchens moves with it.
      def create
        return head :service_unavailable unless Notifications::Vapid.configured?

        PushSubscription.register!(household: current_household, endpoint: params[:endpoint],
                                   p256dh: params.dig(:keys, :p256dh), auth: params.dig(:keys, :auth),
                                   locale: I18n.locale.to_s)
        head :created
      end

      def destroy
        current_household.push_subscriptions.find_by(endpoint: params[:endpoint].to_s)&.destroy!
        head :no_content
      end
    end
  end
end
