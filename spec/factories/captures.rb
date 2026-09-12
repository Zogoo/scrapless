FactoryBot.define do
  factory :capture do
    household
    source { "receipt" }
    status { "pending" }
  end
end
