# 15. Memo Dictation: why "Brot, Milch und Eier" fails, and what to build per phase

*Companion to [doc 13](13-mvp-build.md) and [doc 14](14-mvp-cost-model.md). This doc covers one
screen, the shopping memo, and the one problem reported on it: the mic does not handle German, and
it cannot turn a natural sentence like "I want to buy bread, milk, eggs" into three lines. Every
claim about the code cites the file. Every claim about a vendor or a browser is marked ✅ (checked),
⚠️ (reported by others, not tested here) or ❓ (open).*

> **Verdict.** Most of this is not a speech-recognition problem. Three defects in our own code
> cause most of the damage, and all three are free to fix:
> 1. **The stop button throws the transcript away.** It calls `abort()`, not `stop()` (§15.2.1).
> 2. **Recognition is single-shot.** `continuous = false` ends the session at the first pause, so
>    "bread … milk … eggs" said with natural pauses becomes "bread" (§15.2.2).
> 3. **The memo splitter only splits on commas and "and"/"und".** Browser recognisers rarely put
>    commas in, so "I want to buy bread milk eggs" becomes **one** line, filler words included
>    (§15.2.3, measured).
>
> The German failure has a separate cause. The recogniser's language is the **UI** language, so a
> household that uses the app in English but shops in German is recognised as English. The
> server-side transcription path also sends no language hint at all (§15.2.4).
>
> **Alpha recommendation:** keep the browser's own recogniser, fix the three defects, add a DE/EN
> speech-language toggle beside the mic, and replace the splitter with a dictionary-driven
> segmenter that costs nothing. Give it an optional `gpt-5-nano` fallback for leftovers, off until
> we have measured how often it would fire. **Cost per use stays ≈ $0** on Chrome, Android and iOS
> Safari, and ≈ $0.00075 on the recording fallback. Plan in §15.6.

---

## 15.1 How dictation works today

### The path, end to end

```
memo.html mic button
  └─ Memo.startDictation()                        frontend/src/app/features/memo/memo.ts:127
       ├─ SpeechRecognition available?  (Chrome, Android, Safari ≥14.5)
       │    └─ SpeechService.listen(speechTag(UI locale))   core/services/speech.service.ts:68
       │         lang = 'de-DE' | 'en-GB', continuous = false, interimResults = true
       │         onend → final transcript (string)
       │    └─ MemoService.dictate(text)  POST /api/v1/memo/dictate {transcript}
       └─ else (Firefox, anything without the API)
            └─ MediaRecorder → Blob('audio/webm') → POST /api/v1/memo/dictate (multipart audio)
                 └─ Ai::Transcriber → Ai::Router → Ai::Client#transcribe
                      POST /audio/transcriptions  {model, file}   ← no language, no prompt

MemoItemsController#dictate                       app/controllers/api/v1/memo_items_controller.rb:27
  └─ extract_names(transcript)                    :101
       split on Text::Splitter::SEPARATORS  (, ; \n and und plus)
       strip a leading "buy|get|kauf|hol"
       first 25 parts → one MemoItem each (skipping open duplicates)
```

- **Routes.** `resources :memo_items, path: "memo"` with `post :dictate`
  ([`config/routes.rb`](../config/routes.rb)). `dismiss_suggestion` and `suggestions` sit
  beside it but play no part in dictation.
- **Language selection.** The client picks the recogniser language with `speechTag()`
  ([`speech.service.ts:28`](../frontend/src/app/core/services/speech.service.ts)): `de` maps to
  `de-DE`, and everything else maps to `en-GB`. The input is `translate.currentLang()`, which is
  the UI language chosen by [`LocaleService.initial()`](../frontend/src/app/core/services/locale.service.ts):
  the saved choice, else `navigator.language`, else the default. The same value goes to the
  server as `X-Locale` ([`locale.interceptor.ts`](../frontend/src/app/core/interceptors/locale.interceptor.ts)),
  where it sets `I18n.locale` ([`application_controller.rb`](../app/controllers/application_controller.rb) `set_locale`).
  **On the memo path the server does nothing with it.** Neither the splitter nor the
  transcription request reads `I18n.locale`.
- **Who does the speech-to-text.** On the browser path it is the browser's Web Speech API, which
  is free to us. The server-side path uses `gpt-4o-mini-transcribe` (`Ai::Config::DEFAULT_TRANSCRIBE`)
  or Groq's `whisper-large-v3-turbo`, depending on the provider chain, via
  [`Ai::Client#transcribe`](../app/services/ai/client.rb). The multipart body carries **only**
  `model` and `file` (`post_multipart`), with no `language` and no `prompt`.
- **No model call on the browser path.** The memo deliberately never calls a model (comment at
  `memo_items_controller.rb:98`). That is a good rule, and the alpha keeps it as the default.

### How capture's voice path differs

[`CapturesController#from_voice`](../app/controllers/api/v1/captures_controller.rb) (`:81`) uses
the same client-side `SpeechService` and the same server-side `Ai::Transcriber`, but it parses
through `lines_from` (`:122`):
[`Text::Splitter`](../app/services/text/splitter.rb) splits on the same separators, each part goes
through `ProductAlias.lookup`, and only the parts the dictionary does not know reach
`Ai::TextReader` (`gpt-5-nano`). Capture also enforces `MAX_AUDIO_BYTES`, `MAX_TEXT_CHARS` and the
capture budget. **The memo `dictate` action enforces none of these.**

---

## 15.2 Why it fails

### 15.2.1 The stop button discards everything ✅ (code), ⚠️ (browser behaviour)

`Memo.stopDictation()` calls `this.speech.cancel()` on the recognition path (`memo.ts:147`), and
`cancel()` calls `recognition.abort()` (`speech.service.ts:160`). Per the Web Speech spec,
`abort()` discards pending results. Chromium fires `onerror` with `error: 'aborted'`. Our
`onerror` handler errors the Observable (`speech.service.ts:101`), so `onend`'s
`subscriber.next(finalText)` lands on a closed subscriber and is dropped. The user sees
`capture.no_mic` ("We couldn't hear anything"), even though they were heard.

So the obvious interaction (tap the mic, speak the list, tap the mic to finish) loses the list.
It only works when the user goes silent and lets the browser end the session by itself.
`Capture.stopVoice()` has the same defect (`capture.ts:272`).

### 15.2.2 Single-shot recognition ends at the first pause ✅ (code)

`recognition.continuous = false` (`speech.service.ts:80`). In that mode the recogniser returns one
utterance and ends at the first pause. People reciting a shopping list pause between items, so
"bread … milk … eggs" yields "bread", and the rest is never captured.

A smaller related defect is that `finalText += text` appends per event. On Android Chrome with
`continuous = true`, results are reported cumulatively ⚠️, so appending would duplicate text. The
fix is to rebuild the transcript from `event.results` in full on every event.

### 15.2.3 The splitter needs punctuation the recogniser does not produce ✅ (measured)

`extract_names` splits only on `,`, `;`, newlines, "and", "und" and "plus". It then strips one
leading verb from a fixed list of four words (`memo_items_controller.rb:106`). Chrome's recogniser
generally returns unpunctuated text ⚠️. Measured against the dev dictionary (76 shared aliases)
with `AI_MODE=stub`:

| Transcript | Memo today (`extract_names`) | Capture today (`Text::Splitter`) |
|---|---|---|
| `I want to buy bread milk eggs` | `["I want to buy bread milk eggs"]` (1 line) | `Milk` only, bread and eggs silently lost |
| `I want to buy bread, milk, eggs` | `["I want to buy bread", "milk", "eggs"]` | `Bread, Milk, Eggs` ✅ |
| `bread milk and eggs` | `["bread milk", "eggs"]` | `Milk, Eggs` |
| `ich brauche Brot Milch und Eier` | `["ich brauche Brot Milch", "Eier"]` | `Milch, Eier` |
| `Ich möchte Brot, Milch und Eier kaufen` | `["Ich möchte Brot", "Milch", "Eier kaufen"]` | `Brot, Milch, Eier` ✅ |
| `wir brauchen noch Butter Käse und zwei Gurken` | `["wir brauchen noch Butter Käse", "zwei Gurken"]` | `Butter, Salatgurke` ("Käse" lost) |
| `get some milk and also bananas` | `["some milk", "also bananas"]` | `Milk, Bananen` |

Two findings follow from the table:

- **Memo.** The splitter only works when the recogniser happens to insert commas. Filler phrases
  ("I want to buy", "ich brauche", "wir brauchen noch", a trailing "kaufen") become part of the
  item name.
- **Capture.** It has a **silent data-loss bug** of its own. A chunk holding several foods is
  passed whole to `ProductAlias.lookup`, and `token_match` (`product_alias.rb:67`) returns the
  **single** best-scoring entry, so the other foods vanish without reaching the model. That is a
  case of the dead end doc 4 §4.4 rule 4 forbids, and the comment on `parse_unknown` already warns
  against it.

### 15.2.4 German: the language follows the UI, not the speaker ✅ (code)

The recogniser is told `de-DE` only when the **UI** is German. A Berlin household often runs the
UI in English while the shopping vocabulary is German ("Quark", "Brötchen", "Klopapier"), or the
other way round. In those cases the recogniser is in the wrong language, and nothing in the app
lets the user change it without switching the whole UI language in Settings. Web Speech takes one
`lang` per session and does not auto-detect.

The server path is worse in a different way. It sends no `language`, so the model guesses the
language from a few seconds of audio. Short clips are where language identification is least
reliable ⚠️.

Two lesser issues on the same path:

- **iOS recording is mislabelled ❓.** Safari's `MediaRecorder` records `audio/mp4`, but
  `stopRecording()` wraps the chunks as `new Blob(..., {type: 'audio/webm'})`
  (`speech.service.ts:152`), and `MemoService.dictateAudio` names the file `memo.webm`. Whether the
  transcription endpoint sniffs the container or trusts the extension is untested. Either way, the
  label is wrong.
- **Doc 14's assumption about iOS is out of date.** The code comments and doc 14 §14.2 assume
  Safari has no `SpeechRecognition`. Safari has exposed `webkitSpeechRecognition` since 14.5, so
  iOS Safari users take the free path today. The paid path runs mainly for Firefox. The exception
  is **home-screen (standalone) web apps on iOS**, where recognition has repeatedly been reported
  to fail with `service-not-allowed` ⚠️ ([WebKit bug 225298](https://bugs.webkit.org/show_bug.cgi?id=225298),
  [Apple forum](https://developer.apple.com/forums/thread/748048)). We then show "no mic" and
  never fall back to recording. Our installed-PWA users are exactly the ones who hit this.

### 15.2.5 A correction to doc 14 on privacy

Doc 14 §14.2 says "Chrome and Android do speech recognition **on the device**". By default they
do not ⚠️. Chrome's Web Speech API streams the audio to Google's servers. Chrome now offers a real
on-device mode (`processLocally`, with `SpeechRecognition.available()`/`install()` and roughly
60 MB language packs, per the [blink-dev intent to ship](https://groups.google.com/a/chromium.org/g/blink-dev/c/VNOok2dbmHM)
and [MDN](https://developer.mozilla.org/docs/Web/API/SpeechRecognition/available_static)). The
cost to us is still zero, but the data-residency story in doc 12 should not claim the audio stays
on the phone.

---

## 15.3 What "good" looks like

Acceptance cases, in both languages, with no commas from the recogniser:

| Said | Lines expected |
|---|---|
| "I want to buy bread milk eggs" | Bread · Milk · Eggs |
| "ich brauche Brot Milch und Eier" | Brot · Milch · Eier |
| "wir brauchen noch Butter Käse und zwei Gurken" | Butter · Käse · Gurken (note: 2) |
| "milk toilet paper and something for Sunday" | Milk · toilet paper · something for Sunday |
| "Milch, Klopapier, Brötchen" (English UI) | Milch · Klopapier · Brötchen |

The fourth row matters because a memo line does not have to be food, and the dictionary is
food-only. Unknown words have to survive as their own line, not be dropped and not be glued to the
next item.

---

## 15.4 Options, by phase

Unit of cost is **one dictation of ~15 s**, the same unit doc 14 uses. Prices were checked
November 2026 from vendor pages or aggregators. Recheck them before quoting externally.

### Alpha: the browser's recogniser, used properly, plus a free parser

| | |
|---|---|
| **What** | Web Speech with `continuous = true`, `stop()` not `abort()`, restart on silence until the user taps stop (capped at 30 s), and a DE/EN speech-language toggle. The server splits with a dictionary-driven segmenter (§15.6 step 5). Optional `gpt-5-nano` fallback for unknown leftovers, **off by default**. |
| **Cost per use** | **$0** on Chrome, Android and iOS Safari. **$0.00075** on the recording fallback (0.25 min × $0.003, `gpt-4o-mini-transcribe`). The leftover fallback, if enabled, costs ≈ $0.00006 per call (doc 14's text-parse figure). If it fires on ~1 dictation in 5, that averages ≈ $0.00001. |
| **Latency** | Words appear live (interim results). One server round trip after stop, with no model call in the common case. |
| **Accuracy** | Google's and Apple's recognisers are good in both German and English *when given the right `lang`*. The parser is the limit, and the segmenter is only as good as the dictionary (76 shared aliases + household history today). |
| **iOS Safari** | Works in the browser tab. In the home-screen app ⚠️ it may fail with `service-not-allowed`, so we fall back to recording (paid path) on that error. `continuous` on iOS is reported flaky ⚠️, which is why we restart on `end` rather than trust it. |
| **Android Chrome** | Works. Results arrive cumulatively in continuous mode ⚠️, so rebuild rather than append. Sessions end on silence after a few seconds, which the restart covers. |
| **Complexity** | ~1–1.5 days. No new dependency, no new infrastructure. |
| **Risk** | Audio goes to Google or Apple (§15.2.5). There is no language auto-detect; the toggle is the answer. |

### Beta: one cheap server transcription for everyone who needs it

Use this once the alpha shows where the browser recogniser falls short: mixed-language lists,
iOS home-screen failures, or noisy shops. The idea is to send audio to a cheap transcription model
with a `language` hint and a list-shaped `prompt`, such as "Einkaufsliste: Milch, Brot, Eier,
Klopapier." A comma-separated prompt nudges Whisper-family models toward comma-separated output,
which makes the parser's job easy. Keep the browser recogniser as the free first choice where it
works.

| Provider / model | $/min | **Per 15 s use** | Notes |
|---|---|---|---|
| OpenAI `gpt-4o-mini-transcribe` (already wired) | $0.003 | **$0.00075** | `language` + `prompt` supported. Already the default in `Ai::Config`. |
| Groq `whisper-large-v3-turbo` (already wired as a provider) | $0.04/h | **$0.00017** | 10 s minimum billed per request ([Groq docs](https://console.groq.com/docs/speech-to-text)). US-hosted. Fast. Just set `AI_PROVIDERS` order. |
| Mistral Voxtral Mini Transcribe | ~$0.003 | **~$0.00075** | EU (France) hosting suits doc 12's residency stance. German supported. Needs a new provider entry. Version and price vary by source ⚠️. |
| OpenAI `gpt-4o-transcribe` | $0.006 | $0.0015 | Only if mini proves too weak. |

- **Caps.** Max 30 s per clip, the capture limits (`MAX_AUDIO_BYTES`) on memo too, a per-household
  daily cap (say 20 dictations), and the existing global `Ai::Budget`.
- **Batching** does not help here. Each dictation is one short request; the cost lever is the
  per-request minimum (Groq) and clip length.
- **Volume.** At 3 dictations a week a household costs ≈ $0.01/month on OpenAI mini, or ≈ $0.002
  on Groq. Voice stays far below receipts in doc 14's totals.
- **Latency.** 1–3 s after stop, plus upload. There are no live words while speaking, unless the
  browser recogniser runs alongside for display only.

### v1: on-device first, self-hosted only where it pays

| Option | Per use | Needs | German / English | iOS / Android | Verdict |
|---|---|---|---|---|---|
| **Browser on-device Web Speech** (`processLocally`) | $0 | Chrome with a ~60 MB language pack per language. `install()` needs a user gesture ⚠️ | Same engine family as Google's server recogniser | Chrome desktop yes. Android and iOS ❓ | Adopt where available. Free and private. |
| **Native shell recogniser** (iOS `SFSpeechRecognizer` with `requiresOnDeviceRecognition`; Android `SpeechRecognizer` on-device) | $0 | The thin native shell doc 5 already plans for push | Good in both | Both | **Best v1 answer**. It comes with the shell. |
| **Vosk in the browser** (`vosk-browser` WASM + `vosk-model-small-de-0.15`, 45 MB; English small model ~40 MB) | $0 | Model download on first use. Runs on weak phones | Weaker than Whisper on free speech (WER 13.8 % on Tuda-de per [Vosk's table](https://alphacephei.com/vosk/models)). Small models allow a **runtime vocabulary**, so it could be restricted to our dictionary and filler words ⚠️ | WASM works on both. A 45 MB download on mobile data is a real cost to the user | Interesting fit for a closed vocabulary, poor for "something for Sunday". Prototype only. |
| **Whisper in the browser** (transformers.js on WebGPU, or whisper.cpp WASM) | $0 | 40 MB (tiny) to ~150 MB (base, quantised) download. WebGPU on iOS is version-dependent ⚠️ | tiny and base are noticeably weak in German. small is the usual floor for acceptable German, and too big to download casually | Mid and high-end Android fine. Older iPhones slow | Not worth it while the OS recognisers are free. |
| **whisper.cpp / faster-whisper on the existing app machine** | ≈ $0 marginal | Today's VM is `shared-cpu-1x`, 512 MB ([`fly.toml`](../fly.toml)). whisper.cpp needs ~390 MB for base and ~850 MB for small ⚠️, so bump the VM to 1.5–2 GB (+$6/GB/month ≈ **+$6–9/month**). The machine is already awake while the user uses the app, so there is no cold start. Inference competes with Puma on one shared vCPU: a 15 s clip with small int8 may take several seconds ❓ | base is borderline in German. small is acceptable. A German-fine-tuned small is better | n/a (server) | The cheapest real self-host. Viable once Groq or OpenAI spend exceeds ~$10/month, i.e. tens of thousands of dictations. |
| **Separate ASR machine on Fly** (performance-1x 2 GB, $0.0458/h) | **≈ $0.002–0.004 per isolated use** at low traffic, because a woken machine runs for minutes before auto-stop. Always-on costs **$33/month** ([Fly pricing](https://fly.io/docs/about/pricing/)) | Second machine, volume for the model, cold start of seconds plus model load | Can run large-v3-turbo int8, but only fast enough on dedicated CPU | n/a | **Do not build.** It costs more than Groq per use until ~200k dictations/month. |
| **GPU** (any) | — | Not on a machine that sleeps | — | — | Out of scope. |

The honest v1 picture: **self-hosted server ASR does not beat a $0.04/hour API at our volume.**
The "own, cheap, self-implemented" parts that pay are:

1. **The parser.** The segmenter does the actual work of turning speech into lines, and it is ours
   from the alpha.
2. **On-device recognition.** That means the OS recogniser through the native shell, or Chrome's
   local mode, at a true $0 with audio that never leaves the phone.

A whisper.cpp sidecar on the app machine is the fallback if a provider becomes unacceptable for
privacy rather than for cost.

---

## 15.5 Cost per use, summary

| Phase | Common path | Fallback path | Per household / month (≈13 dictations) |
|---|---|---|---|
| **Alpha** | **$0** (browser recogniser + free segmenter) | $0.00075 (recording → `gpt-4o-mini-transcribe`) | ≈ $0.00–0.01 |
| **Beta** | $0 where the browser recogniser works | **$0.00017** (Groq turbo) to **$0.00075** (OpenAI mini / Voxtral) | ≈ $0.002–0.01 |
| **v1** | **$0** (on-device, OS or Chrome local) | $0.00017 API, or ≈ $0 marginal on a whisper.cpp sidecar (+$6–9/month fixed) | ≈ $0 |

---

## 15.6 Alpha recommendation and implementation plan

**Recommendation.** Keep the browser recogniser and fix how we drive it. Let the user pick the
speech language separately from the UI language. Turn the transcript into lines with a free,
dictionary-driven segmenter shared by memo and capture. Add no new provider and no new
infrastructure. Keep `gpt-5-nano` as a flagged fallback for leftovers, and turn it on only after a
week of logs shows how often it would fire.

The steps, in order. Each is small and testable on its own.

1. **Stop means stop** (`speech.service.ts`, `memo.ts:145`, `capture.ts:272`). Add
   `SpeechService.finish()`, which calls `recognition.stop()`; keep `cancel()` → `abort()` for
   navigation away. Treat `aborted` and `no-speech` as an empty result, not an error.
2. **Continuous listening** (`speech.service.ts:80`). Set `continuous = true`. Rebuild the final
   text from all of `event.results` on every event rather than `+=`. On `end` before the user
   tapped stop, restart, up to a 30 s total cap. Show final plus interim text in the
   `.interim` line so the user sees the whole list growing.
3. **Speech language toggle** (`memo.html`, `speech.service.ts:28`). Add a small `DE | EN` chip
   beside the mic that defaults to the UI locale and is remembered in `localStorage`
   (`scrapless_speech_lang`, wrapped in try/catch like `LocaleService`). Send it as `lang` with
   `dictate` and `dictateAudio`.
4. **Server transcription gets a hint** (`ai/client.rb` `post_multipart`, `ai/transcriber.rb`).
   Pass `language` (`de`/`en`) and a list-shaped `prompt` in that language. Record with
   `recorder.mimeType` and name the file to match (`memo.m4a` on Safari). If recognition fails
   with `service-not-allowed` or `not-allowed` while a constructor exists (iOS home-screen app),
   fall back to recording.
5. **Segmenter** (new `Text::Segmenter`, called from `Text::Splitter` and replacing
   `extract_names`). It runs in five passes:
   1. Normalise with `ProductAlias.normalize_key`.
   2. Split on the existing separators plus "also/auch/sowie/dann/noch/then".
   3. Strip filler from **both** languages whatever the toggle says, because lists are mixed.
      Leading: "i want to buy", "i need (to get)?", "we need", "add", "get", "buy", "pick up",
      "some", "ich brauche", "wir brauchen (noch)?", "ich möchte", "ich will", "kauf(e)?",
      "hol(e)?", "bitte". Trailing: "kaufen", "holen", "besorgen", "please", "bitte".
   4. Inside each remaining chunk, find the **longest dictionary match of up to 3 tokens** from
      left to right. The dictionary is shared aliases, then household aliases, then the
      household's past memo names, then `Memo::Suggester::STAPLES`. Each match becomes a line, and
      each run of unknown tokens between matches becomes its own line (so "toilet paper" survives).
   5. Treat number words ("zwei", "two", "a dozen") before a match as its quantity or note.

   This also fixes capture's silent loss in §15.2.3, because `lines_from` gets one part per food.
6. **Optional leftover fallback.** Only when a chunk has no dictionary hit at all and ≥ 4 tokens,
   send it to `Ai::TextReader` under the already-configured but unused `memo_parse` purpose
   (`ai/config.rb`), using a memo prompt that allows non-food. Put this behind
   `MEMO_AI_FALLBACK=1`, default off. Log the would-have-fired count either way.
7. **Caps on memo dictate** (`memo_items_controller.rb:27`). Apply capture's `MAX_AUDIO_BYTES`,
   `MAX_TEXT_CHARS` and budget check, which the memo path currently lacks.
8. **Tests.**
   - A request spec in `spec/requests/api/v1/memo_items_spec.rb` with the §15.3 table and the
     §15.2.3 sentences as fixtures, run with `AI_MODE=stub`.
   - A unit spec for `Text::Segmenter`.
   - A frontend spec for `SpeechService` with a fake recogniser: stop keeps text, the restart
     accumulates, Android-style cumulative results are not duplicated.
   - A manual pass on a real Android phone and an iPhone, both in the Safari tab and from the
     home screen, because none of the ⚠️ browser behaviours above can be checked without a
     device and a mic.

**Done when** the five sentences in §15.3 produce the expected lines in both UI languages on
Android Chrome and iOS Safari, a tap on stop never loses words, and the cost screen shows zero
billed calls for a browser-path dictation.

---

### Sources

- Code: [`memo_items_controller.rb`](../app/controllers/api/v1/memo_items_controller.rb),
  [`captures_controller.rb`](../app/controllers/api/v1/captures_controller.rb),
  [`speech.service.ts`](../frontend/src/app/core/services/speech.service.ts),
  [`memo.ts`](../frontend/src/app/features/memo/memo.ts),
  [`memo.service.ts`](../frontend/src/app/core/services/memo.service.ts),
  [`locale.service.ts`](../frontend/src/app/core/services/locale.service.ts),
  [`text/splitter.rb`](../app/services/text/splitter.rb),
  [`product_alias.rb`](../app/models/product_alias.rb),
  [`ai/client.rb`](../app/services/ai/client.rb), [`ai/config.rb`](../app/services/ai/config.rb),
  [`ai/transcriber.rb`](../app/services/ai/transcriber.rb), [`fly.toml`](../fly.toml).
- Vendors and browsers: [Groq speech-to-text](https://console.groq.com/docs/speech-to-text) ·
  [OpenAI transcription pricing (aggregated)](https://costgoat.com/pricing/openai-transcription) ·
  [Voxtral Mini Transcribe pricing](https://openrouter.ai/mistralai/voxtral-mini-transcribe/pricing) ·
  [Fly.io pricing](https://fly.io/docs/about/pricing/) ·
  [Vosk models](https://alphacephei.com/vosk/models) ·
  [On-device Web Speech: intent to ship](https://groups.google.com/a/chromium.org/g/blink-dev/c/VNOok2dbmHM) ·
  [MDN `SpeechRecognition.available()`](https://developer.mozilla.org/docs/Web/API/SpeechRecognition/available_static) ·
  [WebKit bug 225298](https://bugs.webkit.org/show_bug.cgi?id=225298) ·
  [transformers.js WebGPU guide](https://huggingface.co/docs/transformers.js/en/guides/webgpu).
