# A display name typed on a phone, not an account.
#
# There is no user row. The phone keeps the name in localStorage and sends it
# with a capture or a memo line; we keep it on that row so the other phones
# sharing the kitchen can see who added it.
module AddedBy
  extend ActiveSupport::Concern

  MAX_NAME_LENGTH = 40

  included do
    validates :added_by_name, length: { maximum: MAX_NAME_LENGTH }, allow_nil: true

    normalizes :added_by_name, with: ->(name) {
      name.to_s.gsub(/[\u0000-\u001F\u007F]/, " ").strip.squeeze(" ").slice(0, MAX_NAME_LENGTH).presence
    }
  end
end
