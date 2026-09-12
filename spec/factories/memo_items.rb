FactoryBot.define do
  factory :memo_item do
    household
    name { "Milk" }
    source { "text" }
  end
end
