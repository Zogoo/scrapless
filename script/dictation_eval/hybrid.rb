# Hybrid = the segmenter's answer when it accounted for every word, the
# model's answer otherwise. Scored like run_gpt.rb, from results already
# collected. Also reports latency percentiles per model.
require "json"
cases = JSON.parse(File.read("dataset.json", encoding: "UTF-8"))
conf = JSON.parse(File.read("confident.json"))
norm = ->(s) { s.to_s.downcase.gsub(/[^\p{L}\p{N}]+/, " ").strip }
seg_ok = cases.map { |c| c["segmenter"].size == c["items"].size && c["items"].zip(c["segmenter"]).all? { |w, g| norm.(w["name"]) == norm.(g["name"]) } }
wrong_but_sure = cases.each_index.select { |i| conf[i] && !seg_ok[i] }
puts "segmenter sure but wrong: #{wrong_but_sure.size}"; wrong_but_sure.each { |i| puts "  #{cases[i]['said']} -> #{cases[i]['segmenter'].map { |p| p['name'] }.join(' · ')}" }
puts "segmenter unsure (model called): #{conf.count(false)} of #{conf.size}; by set: #{cases.each_index.reject { |i| conf[i] }.group_by { |i| cases[i]['set'] }.transform_values(&:size)}"
sets = %w[fixture hard generated_en generated_de ALL]
puts format("%-22s " + "%-13s" * sets.size + " %8s %8s %8s", "hybrid with", *sets, "p50 ms", "p90 ms", "max ms")
Dir["results-*.json"].sort.each do |f|
  rows = JSON.parse(File.read(f, encoding: "UTF-8"))
  cols = sets.map do |set|
    idx = cases.each_index.select { |i| set == "ALL" || cases[i]["set"] == set }
    ok = idx.count { |i| conf[i] ? seg_ok[i] : rows[i]["result"]["names"] }
    format("%3.0f%% (%d/%d)", 100.0 * ok / idx.size, ok, idx.size)
  end
  ms = rows.map { |r| r["result"]["ms"] }.compact.sort
  puts format("%-22s " + "%-13s" * sets.size + " %8d %8d %8d", f[/results-(.+)\.json/, 1], *cols, ms[ms.size / 2], ms[(ms.size * 0.9).floor], ms.last)
end
