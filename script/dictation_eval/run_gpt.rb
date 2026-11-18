# Sends every case in dataset.json to each OpenAI model and scores the answers.
# Plain Ruby, no Rails: it needs nothing but OPENAI_API_KEY, so it cannot touch
# any app database. Usage: ruby run_gpt.rb dataset.json out_dir [model:effort ...]
require "json"
require "net/http"
require "uri"

dataset_path, out_dir, *specs = ARGV
cases = JSON.parse(File.read(dataset_path, encoding: "UTF-8"))
key = ENV["OPENAI_API_KEY"]

# USD per 1M tokens, Standard tier, developers.openai.com/api/docs/pricing (read 2026-11-18).
PRICES = {
  "gpt-6-luna" => [ 0.10, 0.50 ], "gpt-5.4-nano" => [ 0.20, 1.25 ], "gpt-5.6-luna" => [ 0.20, 1.20 ],
  "gpt-5-nano" => [ 0.05, 0.40 ], "gpt-4o-mini" => [ 0.15, 0.60 ], "gpt-5-mini" => [ 0.25, 2.00 ]
}.freeze

# The production prompt and schema, so the eval measures what Memo::ListReader sends.
require_relative "../../app/services/memo/list_prompt"
SCHEMA = Memo::ListPrompt::SCHEMA
SYSTEM = Memo::ListPrompt::SYSTEM

def norm(s) = s.to_s.downcase.gsub(/[^\p{L}\p{N}]+/, " ").strip

def name_ok?(want, got)
  w = norm(want["name"])
  [ got["name"], "#{got['unit']} #{got['name']}", "#{got['unit']} of #{got['name']}" ].any? { |c| norm(c) == w }
end

def score(c, got_items, qty_key: "quantity")
  want = c["items"]
  names = want.size == got_items.size && want.zip(got_items).all? { |w, g| name_ok?(w, g) }
  qtys = names && want.zip(got_items).all? { |w, g| w["qty"].nil? ? g[qty_key].nil? || g[qty_key].to_f == 1.0 : g[qty_key].to_f == w["qty"] }
  food_cases = want.zip(got_items).select { |w, _| !w["food"].nil? }
  food = names && food_cases.all? { |w, g| w["food"] == g["food"] }
  matched = want.count { |w| got_items.any? { |g| name_ok?(w, g) } }
  { "names" => names, "names_qty" => qtys, "food" => food_cases.empty? ? nil : food, "matched" => matched,
    "wanted" => want.size, "got" => got_items.size }
end

def call(model, effort, said, key)
  body = { model: model, messages: [ { role: "system", content: SYSTEM }, { role: "user", content: said } ],
           response_format: { type: "json_schema", json_schema: { name: "memo", strict: true, schema: SCHEMA } } }
  if model.start_with?("gpt-4")
    body[:temperature] = 0
  else
    body[:reasoning_effort] = effort if effort
  end
  uri = URI("https://api.openai.com/v1/chat/completions")
  req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{key}")
  req.body = body.to_json
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
  ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) * 1000).round
  data = JSON.parse(res.body)
  raise "#{res.code} #{data.dig('error', 'message')}" unless res.is_a?(Net::HTTPSuccess)

  u = data["usage"]
  { "items" => JSON.parse(data.dig("choices", 0, "message", "content"))["items"], "ms" => ms,
    "in" => u["prompt_tokens"], "out" => u["completion_tokens"],
    "reasoning" => u.dig("completion_tokens_details", "reasoning_tokens").to_i,
    "cached" => u.dig("prompt_tokens_details", "cached_tokens").to_i }
end

summary = {}
segmenter = cases.map { |c| score(c, c["segmenter"].map { |p| p.merge("food" => nil) }, qty_key: "qty") }
summary["segmenter"] = { "results" => segmenter }

specs.each do |spec|
  model, effort = spec.split(":")
  queue = Queue.new
  cases.each_with_index { |c, i| queue << [ c, i ] }
  results = Array.new(cases.size)
  Array.new(6) do
    Thread.new do
      while (job = (queue.pop(true) rescue nil))
        c, i = job
        begin
          r = call(model, effort, c["said"], key)
          results[i] = r.merge(score(c, r["items"]))
        rescue => e
          results[i] = { "error" => e.message[0, 200] }
        end
      end
    end
  end.each(&:join)
  summary[spec] = { "results" => results }
  failed = results.select { |r| r["error"] }
  warn "#{spec}: #{failed.size} of #{results.size} calls failed, e.g. #{failed.first["error"]}" if failed.any?
  warn "#{spec}: done"
  File.write(File.join(out_dir, "results-#{spec.tr(':', '_')}.json"), JSON.pretty_generate(cases.zip(results).map { |c, r| { "said" => c["said"], "set" => c["set"], "want" => c["items"], "result" => r } }))
end

sets = cases.map { |c| c["set"] }.uniq
puts format("%-22s %-14s %8s %8s %8s %8s %8s %9s %9s %7s", "model", "set", "lists", "+qty", "food", "items", "errors", "in/out", "USD/1k", "p50ms")
summary.each do |name, s|
  model = name.split(":").first
  (sets + [ "ALL" ]).each do |set|
    idx = cases.each_index.select { |i| set == "ALL" || cases[i]["set"] == set }
    rs = idx.map { |i| s["results"][i] }
    ok = rs.reject { |r| r["error"] }
    pct = ->(k) { ok.empty? ? "-" : format("%.0f%%", 100.0 * ok.count { |r| r[k] } / ok.size) }
    food_rs = ok.reject { |r| r["food"].nil? }
    food = food_rs.empty? ? "-" : format("%.0f%%", 100.0 * food_rs.count { |r| r["food"] } / food_rs.size)
    items = format("%.0f%%", 100.0 * ok.sum { |r| r["matched"] } / [ ok.sum { |r| r["wanted"] }, 1 ].max)
    if ok.first&.key?("in")
      inp = ok.sum { |r| r["in"] } / ok.size.to_f
      out = ok.sum { |r| r["out"] } / ok.size.to_f
      pin, pout = PRICES.fetch(model)
      usd = (inp * pin + out * pout) / 1_000_000 * 1000
      ms = ok.map { |r| r["ms"] }.sort[ok.size / 2]
      tok = format("%.0f/%.0f", inp, out)
      cost = format("$%.4f", usd)
    end
    puts format("%-22s %-14s %8s %8s %8s %8s %8d %9s %9s %7s", name, set, pct.("names"), pct.("names_qty"), food, items,
                rs.count { |r| r["error"] }, tok || "-", cost || "-", ms || "-")
  end
end
