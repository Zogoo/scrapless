#!/bin/sh
# Doc 15 §15.11: does a GPT model split a spoken shopping sentence better than
# Text::Segmenter, and what does it cost? Run from the repository root:
#
#   script/dictation_eval/run.sh [model:effort ...]
#
# Uses a throwaway database under tmp/dictation_eval, never DATABASE_PATH from
# .env, so the development database is not touched. The GPT step is plain Ruby
# and needs only OPENAI_API_KEY (from the environment, or the repo's .env).
# The default five models cost about $0.07 in total at 2026-11-18 list prices.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EVAL="$ROOT/script/dictation_eval"
OUT="$ROOT/tmp/dictation_eval"
DB="$OUT/eval.sqlite3"
export LANG=en_US.UTF-8
mkdir -p "$OUT"
[ $# -gt 0 ] || set -- gpt-6-luna:none gpt-6-luna:low gpt-5.4-nano:none gpt-5-nano:minimal gpt-4o-mini

cd "$ROOT"
rm -f "$DB"
RAILS_ENV=test DATABASE_PATH="$DB" bin/rails db:schema:load >/dev/null
RAILS_ENV=test DATABASE_PATH="$DB" bin/rails runner "$EVAL/build_dataset.rb" "$EVAL/hard.yml" "$OUT/dataset.json"
RAILS_ENV=test DATABASE_PATH="$DB" bin/rails runner "$EVAL/confident.rb" "$OUT/dataset.json" "$OUT/confident.json"
sqlite3 -separator '|' "$DB" "select raw_text, canonical_name from product_aliases where household_id is null" > "$OUT/aliases.txt"

if [ -z "$OPENAI_API_KEY" ] && [ -f "$ROOT/.env" ]; then
  OPENAI_API_KEY="$(grep -E '^(export[[:space:]]+)?OPENAI_API_KEY=' "$ROOT/.env" | head -1 | sed -E 's/^(export[[:space:]]+)?OPENAI_API_KEY=//' | tr -d "\"' ")"
fi
[ -n "$OPENAI_API_KEY" ] || { echo "OPENAI_API_KEY is not set" >&2; exit 1; }
export OPENAI_API_KEY

cd "$OUT"
ruby "$EVAL/run_gpt.rb" dataset.json . "$@" | tee summary.txt
ruby "$EVAL/rescore.rb" | tee spoken-subset.txt
ruby "$EVAL/hybrid.rb" | tee hybrid.txt
echo "results in $OUT"
