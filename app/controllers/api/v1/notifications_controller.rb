module Api
  module V1
    # The one outcome a notification can report: someone opened it. Doc 5 §5.5
    # lowers the budget for a kitchen that keeps ignoring them; this is the
    # first half of that measurement.
    class NotificationsController < ApplicationController
      def opened
        notification = current_household.notifications.find(params[:id])
        notification.update!(opened_at: Time.current) if notification.opened_at.nil?
        head :no_content
      end
    end
  end
end
