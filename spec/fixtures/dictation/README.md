# Dictation evaluation set

One file per language (plus `mixed.yml`), each a list of `said` → `lines`
cases that `spec/services/text/segmenter_spec.rb` runs against the seeded
dictionary. Adding a case is adding data here, not code.

The cases below are the acceptance sentences from doc 15 §15.3. Replace and
grow them with real transcripts from the Berlin concierge test (doc 15
§15.8.5): what the recogniser actually returned, and the lines the household
kept after correcting them.
