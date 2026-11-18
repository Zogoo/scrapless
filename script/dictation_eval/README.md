# Dictation eval: segmenter vs GPT

Measures how well `Text::Segmenter` and a few OpenAI models turn one spoken
shopping sentence into list lines, and what each model costs. Findings are in
[doc 15 §15.11](../../docs/15-memo-dictation.md#1511-an-llm-as-the-splitter-measured-cost-and-quality-).

```sh
script/dictation_eval/run.sh                       # the five models of 2026-11-18
script/dictation_eval/run.sh gpt-6-luna:none       # or any model:reasoning_effort
```

| File | What it does |
|---|---|
| `hard.yml` | 20 hand-written sentences with the expected items. **Not from real users**: there is no dictation log yet. Grow it from real failures. |
| `build_dataset.rb` | Rails runner. Adds `spec/fixtures/dictation/*.yml` and 60 generated lists per locale (the generator from `segmenter_spec.rb`), and records the segmenter's answer to each. |
| `confident.rb` | Rails runner. Whether the segmenter accounted for every word with the lexicon: the gate a hybrid would use before calling a model. |
| `run_gpt.rb` | Plain Ruby, no Rails or database. Calls each model with one language-agnostic prompt and a strict JSON schema, and scores list exactness, quantities, food flags, tokens, cost and latency. |
| `rescore.rb` | Rescores the generated lists on the subset a person could say: no receipt abbreviations or `ae`/`oe` spellings, no two names for the same product. |
| `hybrid.rb` | Scores "segmenter when sure, model otherwise", plus latency percentiles. |
| `results/` | The tables from the run quoted in doc 15. |

Prices in `run_gpt.rb` are the Standard tier from
[OpenAI's pricing page](https://developers.openai.com/api/docs/pricing), read on
2026-11-18. Update them before quoting a new run.
