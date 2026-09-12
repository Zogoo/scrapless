FactoryBot.define do
  factory :product_alias do
    raw_text { "brokkoli" }
    canonical_name { "Brokkoli" }
    category { "produce" }
    emoji { "🥦" }
  end
end
