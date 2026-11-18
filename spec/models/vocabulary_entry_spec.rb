require "rails_helper"

RSpec.describe VocabularyEntry do
  subject { build(:vocabulary_entry) }

  it { is_expected.to validate_inclusion_of(:kind).in_array(described_class::KINDS) }
  it { is_expected.to validate_uniqueness_of(:phrase).scoped_to(:household_id, :kind).ignoring_case_sensitivity }

  it "stores phrases the way the dictionary compares them" do
    expect(create(:vocabulary_entry, phrase: "Ich hätt' gern").phrase).to eq("ich haett gern")
  end
end
