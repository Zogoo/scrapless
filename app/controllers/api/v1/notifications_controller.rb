module Api
  module V1
    # The bell: what this kitchen was told, and what someone has read.
    #
    # Read is per kitchen, not per phone. Opening one also counts it as opened,
    # which doc 5 §5.5 uses to lower the budget for a kitchen that keeps
    # ignoring them.
    class NotificationsController < ApplicationController
      def index
        render json: Notifications::Inbox.call(household: current_household)
      end

      def read
        notification = current_household.notifications.find(params[:id])
        notification.update!(opened_at: Time.current) if notification.opened_at.nil?
        head :no_content
      end

      def read_all
        current_household.notifications.where(opened_at: nil).update_all(opened_at: Time.current, updated_at: Time.current)
        head :no_content
      end
    end
  end
end
