module EnvHelpers
  # Sets ENV for one block and puts every key back, set or unset, afterwards.
  def with_env(values)
    saved = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  # Push keys, so the feature is on for the example.
  def vapid_env = { "VAPID_PUBLIC_KEY" => "BPublicKeyForSpecs", "VAPID_PRIVATE_KEY" => "private-key-for-specs" }
end

RSpec.configure do |config|
  config.include EnvHelpers
  config.include ActiveSupport::Testing::TimeHelpers
end
