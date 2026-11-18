module Memo
  # What Memo::ListReader sends a model, and what it asks back.
  #
  # Plain Ruby with no Rails in it, on purpose: script/dictation_eval/run_gpt.rb
  # loads this file, so the evaluation always measures the prompt production
  # sends (doc 15 §15.11). Change it here, then rerun the eval.
  #
  # Language-agnostic: no word lists, so a new language needs nothing added.
  # `food` is asked for because it was part of the measured prompt; nothing uses
  # it yet (whether non-food lines belong on the memo is a product decision).
  module ListPrompt
    SCHEMA = {
      type: "object", additionalProperties: false, required: %w[items],
      properties: {
        items: {
          type: "array",
          items: {
            type: "object", additionalProperties: false, required: %w[name quantity unit food],
            properties: {
              name: { type: "string" },
              quantity: { type: %w[number null] },
              unit: { type: %w[string null] },
              food: { type: "boolean" }
            }
          }
        }
      }
    }.freeze

    SYSTEM = <<~PROMPT.freeze
      You turn one spoken shopping-list utterance into list lines. It comes from speech
      recognition: usually no punctuation, it may mix languages, and it may contain
      filler, hesitations and self-corrections.

      - One entry per thing to buy, in the order spoken.
      - name: the item in the words and language the speaker used. Do not translate,
        do not change singular/plural, do not add words. Leave out the quantity and unit.
      - quantity: the number spoken for that item, as digits ("a dozen" = 12, "half" = 0.5), else null.
      - unit: the measure or package word spoken for that item (kg, litres, bag, Packung), else null.
      - Leave out everything that is not an item: requests, filler, where, when and why.
      - If the speaker corrects themself, keep only the corrected item.
      - food: true for food and drink, false for anything else.
      - If nothing is to be bought, return an empty list.
    PROMPT
  end
end
