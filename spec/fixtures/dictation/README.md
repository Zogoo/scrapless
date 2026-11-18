# Dictation evaluation set

One file per language (plus `mixed.yml`), each a list of `said` → `lines`
cases: the lines the memo should end up with (`Memo::ListReader`). Adding a
case is adding data here, not code.

`spec/services/text/segmenter_spec.rb` runs them against the seeded
dictionary: the segmenter must give exactly these lines, or report itself
unsure so a model reads the sentence instead. Being confidently wrong fails.
`script/dictation_eval` runs them through the model and the whole reader.

The cases below are the acceptance sentences from doc 15 §15.3. Replace and
grow them with real transcripts from the Berlin concierge test (doc 15
§15.8.5): what the recogniser actually returned, and the lines the team
judges right when reviewing that test. Users are never asked to correct
anything.
