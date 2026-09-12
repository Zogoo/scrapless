FactoryBot.define do
  factory :shelf_life_rule do
    category { "produce" }
    storage { "fridge" }
    days_p50 { 5 }
    days_p90 { 9 }
    consume_p50 { 5 }
    high_risk { false }
  end
end
