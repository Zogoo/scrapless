# rails runner: for each case, did the segmenter account for every word with
# the lexicon (each line = optional amount/unit/modifier + a known item)?
# That is the gate a hybrid would use to decide whether to call a model.
require "json"
Text::Lexicon.reset!
lex = Text::Lexicon.for(nil)
cases = JSON.parse(File.read(ARGV[0], encoding: "UTF-8"))
flags = cases.map do |c|
  parts = Text::Segmenter.call(text: c["said"]).parts
  parts.all? do |line|
    words = ProductAlias.normalize_key(line).split
    words = words.drop(1) while words.any? && (words.first.match?(/\A\d/) || lex.units.include?(words.first) || lex.modifiers.include?(words.first))
    lex.items.include?(words.join(" "))
  end
end
File.write(ARGV[1], JSON.generate(flags))
puts "confident on #{flags.count(true)} of #{flags.size}"
