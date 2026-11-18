require "rails_helper"

RSpec.describe Ai::Language do
  it "names the person's app language for the prompt" do
    expect(I18n.with_locale(:de) { described_class.name }).to eq("German")
    expect(described_class.name(:en)).to eq("English")
  end

  # Every configured language must name itself, or its users' answers would
  # silently come back in the default language.
  it "has a name for every configured language" do
    I18n.available_locales.each do |locale|
      expect(I18n.exists?("language.english_name", locale)).to be(true), "#{locale} has no language.english_name"
    end
  end
end
