require "spec_helper"
ENV["RAILS_ENV"] = "test"

# The suite must be hermetic: it may not spend money and it may not touch a real
# database.
#
# Both hazards come from the same place. dotenv-rails loads .env in the test
# environment as well, and .env carries development values — a real
# OPENAI_API_KEY with AI_MODE=auto, and DATABASE_PATH pointing at the
# development SQLite file. Left alone, `bundle exec rspec` bills every example
# that touches a capture and runs the whole suite, truncations included, against
# the developer's own data.
#
# Forced here, before the app boots, because this is the one file every example
# loads. Set AI_MODE=live on the command line if you ever genuinely want a test
# to call out.
ENV["AI_MODE"] = "stub" unless ENV["AI_MODE"] == "live"
ENV["DATABASE_PATH"] = "storage/test.sqlite3"

require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "shoulda-matchers"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
