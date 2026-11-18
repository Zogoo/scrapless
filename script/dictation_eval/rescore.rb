# Re-scores the generated lists on the subset a person could actually say:
# every entry is spelled as spoken (raw text == canonical name, so no receipt
# abbreviations or ae/oe transliterations), and no two entries name the same
# product. Uses the results already collected; no new calls.
require "json"
canon = File.readlines("aliases.txt", chomp: true, encoding: "UTF-8").to_h { |l| l.split("|", 2) }
norm = ->(s) { s.to_s.downcase.gsub(/[^\p{L}\p{N}]+/, " ").strip }
spoken = lambda do |row|
  names = row["want"].map { |w| w["name"] }
  names.all? { |n| norm.(canon.fetch(n, n)) == norm.(n) } && names.map { |n| canon.fetch(n, n) }.uniq.size == names.size
end
files = Dir["results-*.json"].sort
dataset = JSON.parse(File.read("dataset.json", encoding: "UTF-8"))
puts format("%-22s %-14s %6s %8s %8s", "model", "subset", "cases", "lists", "items")
%w[generated_en generated_de].each do |set|
  idx = dataset.each_index.select { |i| dataset[i]["set"] == set && spoken.({ "want" => dataset[i]["items"] }) }
  # segmenter: same scoring as run_gpt.rb (exact line names in order)
  seg_ok = idx.count { |i| c = dataset[i]; c["segmenter"].size == c["items"].size && c["items"].zip(c["segmenter"]).all? { |w, g| norm.(w["name"]) == norm.(g["name"]) } }
  puts format("%-22s %-14s %6d %7.0f%% %8s", "segmenter", "#{set}*", idx.size, 100.0 * seg_ok / idx.size, "-")
  files.each do |f|
    rows = JSON.parse(File.read(f, encoding: "UTF-8"))
    ok = idx.map { |i| rows[i]["result"] }.reject { |r| r["error"] }
    puts format("%-22s %-14s %6d %7.0f%% %7.0f%%", f[/results-(.+)\.json/, 1], "#{set}*", ok.size,
                100.0 * ok.count { |r| r["names"] } / ok.size, 100.0 * ok.sum { |r| r["matched"] } / ok.sum { |r| r["wanted"] })
  end
end
