module Notifications
  # Enqueued by each tick; see Notifications::Dispatch.
  class DispatchJob < ApplicationJob
    queue_as :default

    def perform = Dispatch.call
  end
end
