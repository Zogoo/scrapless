# rails runner: builds the evaluation set as JSON and records the segmenter's
# answer for each case, so both are scored the same way.
# Usage: RAILS_ENV=test DATABASE_PATH=<scratch db> bin/rails runner build_dataset.rb <hard.yml> <out.json>
require "json"

hard_path, out_path = ARGV
Rails.application.load_seed
Text::Lexicon.reset!

def parse_line(line)
  qty = line[/\A(\d+(?:\.\d+)?)\s/, 1]
  { "name" => qty ? line.sub(/\A\S+\s+/, "") : line, "qty" => qty&.to_f }
end

cases = []

Dir[Rails.root.join("spec/fixtures/dictation/*.yml")].sort.each do |file|
  YAML.safe_load_file(file).each do |ex|
    cases << { "set" => "fixture", "said" => ex["said"], "items" => ex["lines"].map { |l| parse_line(l).merge("food" => nil) } }
  end
end

YAML.safe_load_file(hard_path).each do |ex|
  cases << { "set" => "hard", "said" => ex["said"],
             "items" => ex["items"].map { |i| { "name" => i["name"].to_s, "qty" => i["qty"]&.to_f, "food" => i["food"] } } }
end

# The same generator as spec/services/text/segmenter_spec.rb "generated lists".
lexicon = Text::Lexicon.for(nil)
reserved = lexicon.leading | lexicon.trailing | lexicon.separators | lexicon.modifiers | lexicon.units | lexicon.numbers.keys.to_set
items = ProductAlias.shared.pluck(:raw_text).uniq.reject { |raw| raw.split.any? { |w| reserved.include?(w) || w.match?(/\d/) } }
random = Random.new(42)
Dictation::Vocabulary.locales.each do |locale|
  language = Dictation::Vocabulary.for(locale)
  60.times do
    chosen = items.sample(random.rand(2..5), random: random)
    glue = [ " ", " #{language.separators.sample(random: random)} " ]
    said = chosen.map.with_index { |item, i| i.zero? ? item : glue.sample(random: random) + item }.join
    said = "#{language.leading.sample(random: random)} #{said} #{language.trailing.sample(random: random)}"
    cases << { "set" => "generated_#{locale}", "said" => said, "items" => chosen.map { |c| { "name" => c, "qty" => nil, "food" => nil } } }
  end
end

cases.each do |c|
  c["segmenter"] = Text::Segmenter.call(text: c["said"], household: nil).parts.map { |l| parse_line(l) }
end

File.write(out_path, JSON.pretty_generate(cases))
puts "#{cases.size} cases: #{cases.group_by { |c| c['set'] }.transform_values(&:size)}"
