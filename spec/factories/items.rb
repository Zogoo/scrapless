FactoryBot.define do
  factory :item do
    household
    display_name { "Brokkoli" }
    canonical_name { "brokkoli" }
    category { "produce" }
    storage { "fridge" }
    acquired_on { Date.current }
    window_start { Date.current + 4 }
    window_end { Date.current + 9 }
    confidence { 0.6 }

    # Bought far enough in the past that the spoilage ramp has opened.
    trait :at_risk do
      acquired_on { Date.current - 8 }
      window_start { Date.current - 4 }
      window_end { Date.current + 1 }
    end

    trait :ghost do
      acquired_on { Date.current - 20 }
      window_start { Date.current - 16 }
      window_end { Date.current - 11 }
    end
  end
end
