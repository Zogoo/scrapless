FactoryBot.define do
  factory :notification do
    household
    sent_on { Date.current }
    iso_week { Notification.week_of(sent_on) }
    slot { 1 }
    item_ids { [] }
  end
end
