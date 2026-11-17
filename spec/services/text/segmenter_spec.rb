require "rails_helper"

# These examples are built to find what the rules miss, not to restate them:
# an evaluation set kept as data, lists generated from the real seeded
# dictionary and every phrase in config/dictation, and an invariant over
# random input.
RSpec.describe Text::Segmenter do
  before do
    Rails.application.load_seed
    Text::Lexicon.reset!
  end

  def parts(text, household: nil) = described_class.call(text: text, household: household).parts
  def key(text) = ProductAlias.normalize_key(text)

  describe "the evaluation set (spec/fixtures/dictation)" do
    Dir[Rails.root.join("spec/fixtures/dictation/*.yml")].sort.each do |file|
      YAML.safe_load_file(file).each do |example|
        it "#{File.basename(file, '.yml')}: #{example['said'].inspect}" do
          expect(parts(example["said"])).to eq(example["lines"])
        end
      end
    end
  end

  # Lists of real dictionary entries, in every language, with every filler and
  # separator the data knows, no punctuation: each item must come back alone.
  describe "generated lists" do
    let(:lexicon) { Text::Lexicon.for(nil) }
    let(:random) { Random.new(RSpec.configuration.seed) }
    let(:reserved) do
      lexicon.leading | lexicon.trailing | lexicon.separators | lexicon.modifiers | lexicon.units |
        lexicon.numbers.keys.to_set
    end
    # Entries that are also a filler or unit word cannot be said alone and
    # recognised as an item, by definition; everything else is fair game.
    let(:items) do
      ProductAlias.shared.pluck(:raw_text).uniq.reject do |raw|
        raw.split.any? { |word| reserved.include?(word) || word.match?(/\d/) }
      end
    end

    # Two neighbours that together spell a longer known phrase are one item.
    def spans_known_phrase?(chosen)
      words = chosen.flat_map(&:split)
      (2..lexicon.items_longest).any? do |n|
        words.each_cons(n).any? { |run| lexicon.items.include?(run.join(" ")) && !chosen.include?(run.join(" ")) }
      end
    end

    Dictation::Vocabulary.locales.each do |locale|
      it "recovers every item from 200 generated #{locale} lists" do
        language = Dictation::Vocabulary.for(locale)
        failures = []
        tried = 0

        200.times do
          chosen = items.sample(random.rand(2..5), random: random)
          next if spans_known_phrase?(chosen)

          tried += 1

          glue = [ " ", " #{language.separators.sample(random: random)} " ]
          said = chosen.map.with_index { |item, i| i.zero? ? item : glue.sample(random: random) + item }.join
          said = "#{language.leading.sample(random: random)} #{said} #{language.trailing.sample(random: random)}"

          got = parts(said).map { |part| key(part) }
          failures << [ said, got ] unless got == chosen
        end

        expect(tried).to be > 150
        expect(items.size).to be > 40
        expect(failures).to be_empty, failures.first(5).map { |said, got| "#{said.inspect} -> #{got}" }.join("\n")
      end
    end
  end

  # Whatever is said, nothing but known filler and separators is thrown away.
  it "never drops a word it does not know as filler" do
    lexicon = Text::Lexicon.for(nil)
    droppable = lexicon.leading | lexicon.trailing | lexicon.separators
    random = Random.new(RSpec.configuration.seed)
    vocabulary = ProductAlias.shared.pluck(:raw_text) + %w[quark yuzu tortillas something nice weekend zwiebeln]

    300.times do
      said = Array.new(random.rand(1..8)) { vocabulary.sample(random: random) }.join(" ")
      kept = parts(said).flat_map { |part| key(part).split }
      lost = key(said).split - kept

      expect(lost.reject { |word| droppable.include?(word) }).to be_empty, "#{said.inspect} lost #{lost}"
    end
  end

  it "reports a group of several words it could not split at all" do
    expect(described_class.call(text: "something nice for the weekend party").unresolved)
      .to eq([ "something nice for the weekend party" ])
  end

  describe "what a kitchen has taught it" do
    let(:household) { create(:household) }

    it "keeps a phrase it learned as one line" do
      create(:vocabulary_entry, household: household, kind: "item", phrase: "hafer milch")

      expect(parts("hafer milch brot", household: household)).to eq([ "hafer milch", "brot" ])
      expect(parts("hafer milch brot")).to eq(%w[hafer milch brot])
    end

    it "drops filler it learned, in that kitchen only" do
      create(:vocabulary_entry, household: household, kind: "leading", phrase: "ich hätt gern")

      expect(parts("ich hätt gern Milch", household: household)).to eq([ "Milch" ])
      expect(parts("ich hätt gern Milch", household: create(:household))).to eq([ "ich hätt gern", "Milch" ])
    end

    it "learns from lines a person typed, not from lines the mic wrote" do
      create(:memo_item, household: household, name: "Hafer Milch", source: "text")
      create(:memo_item, household: household, name: "bread milk", source: "voice")

      expect(parts("hafer milch bread milk", household: household)).to eq([ "hafer milch", "bread", "milk" ])
    end
  end
end
