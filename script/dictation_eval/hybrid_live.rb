# Rails runner: every case through the real Memo::ListReader, live, exactly as
# the dictate endpoint calls it. Unlike hybrid.rb, nothing is simulated: the
# gate, the model, the timeout, the grounding check and the fallback are the
# production code. Needs AI_MODE=live and OPENAI_API_KEY (run.sh sets both).
# Usage: bin/rails runner hybrid_live.rb dataset.json out.json
require "json"

dataset_path, out_path = ARGV
Rails.application.load_seed
Text::Lexicon.reset!
cases = JSON.parse(File.read(dataset_path, encoding: "UTF-8"))
household = Household.first || Household.create!(name: "Dictation eval")

def norm(text) = text.to_s.downcase.gsub(/[^\p{L}\p{N}]+/, " ").strip

# A line is "2 Kilo Kartoffeln": it matches when it is the expected name, or
# ends with it after an amount and unit.
def line_ok?(want, line)
  w = norm(want["name"])
  l = norm(line)
  l == w || (l.end_with?(" #{w}") && l.split.first.match?(/\A\d/))
end

rows = cases.map do |c|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  reading = Memo::ListReader.call(text: c["said"], household: household)
  ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  ok = reading.lines.size == c["items"].size && c["items"].zip(reading.lines).all? { |w, l| line_ok?(w, l) }
  { "set" => c["set"], "said" => c["said"], "lines" => reading.lines, "path" => reading.path,
    "reason" => reading.reason, "model_ms" => reading.model_ms, "total_ms" => ms, "ok" => ok }
end
File.write(out_path, JSON.pretty_generate(rows))

calls = AiCall.where(purpose: "memo_parse")
puts "Memo::ListReader, AI mode #{Ai::Config.mode}, #{rows.size} cases"
puts format("%-14s %6s %10s", "set", "right", "model used")
(rows.map { |r| r["set"] }.uniq + [ "ALL" ]).each do |set|
  rs = rows.select { |r| set == "ALL" || r["set"] == set }
  puts format("%-14s %3d/%-3d %5d", set, rs.count { |r| r["ok"] }, rs.size, rs.count { |r| r["path"] != "segmenter" })
end
puts "paths: #{rows.group_by { |r| "#{r['path']}/#{r['reason']}" }.transform_values(&:size)}"
ms = rows.filter_map { |r| r["model_ms"] }.sort
puts "model wait ms: median #{ms[ms.size / 2]}, p90 #{ms[(ms.size * 0.9).floor]}, max #{ms.last}" if ms.any?
puts format("model calls: %d, cost $%.6f total, $%.6f per call", calls.count, calls.sum(:cost_micros) / 1e6,
            calls.count.zero? ? 0 : calls.sum(:cost_micros) / 1e6 / calls.count)
rows.reject { |r| r["ok"] }.each { |r| puts "  wrong [#{r['path']}/#{r['reason']}] #{r['said']} -> #{r['lines'].join(' · ')}" }
