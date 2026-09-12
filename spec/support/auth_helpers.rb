module AuthHelpers
  # There is no sign-in step to simulate: a fridge is its token.
  def fridge_headers(household)
    { "Authorization" => "Bearer #{household.token}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
