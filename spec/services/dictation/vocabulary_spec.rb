require "rails_helper"

# The app's languages are listed once per stack; these keep the lists and
# their data from drifting apart.
RSpec.describe Dictation::Vocabulary do
  it "has dictation data with every key for every locale the app offers" do
    I18n.available_locales.each do |locale|
      language = described_class.for(locale)

      expect(language.transcription_prompt).to be_present
      expect([ language.separators, language.leading, language.numbers ]).to all(be_present)
    end
  end

  it "has no dictation data for a locale the app does not offer" do
    files = Dir[Rails.root.join("config/dictation/*.yml")].map { |f| File.basename(f, ".yml") }

    expect(files).to match_array(I18n.available_locales.map(&:to_s))
  end

  it "offers the same languages as the frontend" do
    %w[environment.ts environment.prod.ts].each do |file|
      source = Rails.root.join("frontend/src/environments", file).read
      frontend = source[/availableLocales:\s*\[([^\]]*)\]/, 1].scan(/'([^']+)'/).flatten

      expect(frontend).to match_array(I18n.available_locales.map(&:to_s)), file
    end
  end

  it "has an UI translation file for every locale" do
    I18n.available_locales.each do |locale|
      expect(Rails.root.join("frontend/src/assets/i18n/#{locale}.json")).to exist
    end
  end
end
