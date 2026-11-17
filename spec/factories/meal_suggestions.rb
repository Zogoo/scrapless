FactoryBot.define do
  factory :meal_suggestion do
    household
    meal { "dinner" }
    served_on { Date.current }
    locale { "en" }
    body { "[]" }
  end
end
