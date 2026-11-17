# What one request may send, in one place for every endpoint that takes free
# text or audio. Bounds on cost and abuse, not properties of shopping lists.
module InputLimits
  MAX_IMAGE_BYTES = 8.megabytes
  MAX_AUDIO_BYTES = 12.megabytes
  # A typed or spoken shop is a few dozen words. Past this it is not a
  # shopping list, and in live mode every character can reach a paid model.
  MAX_TEXT_CHARS = 1_000
  # There is no account wall in front of these endpoints — a fridge is free to
  # create — so the blast radius of a loop is bounded per kitchen and hour.
  # Roughly twenty times the heaviest plausible real week, in one hour.
  MAX_CAPTURES_PER_HOUR = 40
  MAX_TRANSCRIPTIONS_PER_HOUR = 40
end
