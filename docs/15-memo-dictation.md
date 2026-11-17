# 15. Memo Dictation: why "Brot, Milch und Eier" fails, and what to build per phase

*Companion to [doc 13](13-mvp-build.md) and [doc 14](14-mvp-cost-model.md). This doc covers one
screen, the shopping memo, and the one problem reported on it: the mic does not handle German, and
it cannot turn a natural sentence like "I want to buy bread, milk, eggs" into three lines.*

**How claims are marked.** No figure or behaviour here is a guess.

| Mark | Meaning |
|---|---|
| ✅ | Checked against a primary source: the spec, the vendor's own docs or pricing page, browser source code, MDN's browser-compat-data, or a peer-reviewed paper. The source is linked inline. |
| 🧪 | Measured in this repository or this machine. The command is described. |
| ⚠️ | Reported by more than one independent community source, but not confirmed by a primary source or on a device. Not relied on in the plan. |
| ❓ | Unverified. Stated only as an open question, never as a basis for a decision. |

*Verified 2026-11-17. Prices and browser support change, so recheck before quoting externally.*

> **Verdict.** Most of this is not a speech-recognition problem. Three defects in our own code
> cause most of the damage, and all three are free to fix:
> 1. **The stop button throws the words away.** It calls `abort()`, and the spec says `abort()`
>    returns no result (§15.2.1).
> 2. **Recognition ends at the first pause, and on Android Chrome `continuous` cannot fix it.**
>    MDN's compat data says the property "can be set, but has no effect" there (§15.2.2).
> 3. **The memo splitter needs commas the recogniser does not produce.** "I want to buy bread milk
>    eggs" becomes **one** line (§15.2.3, measured).
>
> The German failure has a separate cause. The recogniser's language is the **UI** language, and
> the server-side transcription request sends no language hint at all (§15.2.4).
>
> **Alpha recommendation (revised 2026-11-17):** the alpha is about **German and English
> working equally well**, not about long continuous dictation.
> - Keep the browser's own recogniser, single-shot. Continuous listening is **dropped from the
>   alpha**; its research stays in §15.2.2 for later.
> - Make the mic **hold to talk, tap to toggle**: hold, say one item or a few, release, and the
>   lines appear (§15.8).
> - Fix stop to use `stop()`.
> - Add a DE/EN speech-language toggle beside the mic, and send the language to the server.
> - Replace the splitter with a dictionary-driven segmenter that costs nothing.
>
> **Cost per use stays $0** wherever the browser recogniser exists, and **$0.00075** per 15 s on
> the recording fallback (§15.5). Plan in §15.6.

---

## 15.1 How dictation works today 🧪 (code read on `origin/main` 6bcdf3c)

### The path, end to end

```
memo.html mic button
  └─ Memo.startDictation()                        frontend/src/app/features/memo/memo.ts:127
       ├─ window.SpeechRecognition || webkitSpeechRecognition exists?
       │    └─ SpeechService.listen(speechTag(UI locale))   core/services/speech.service.ts:68
       │         lang = 'de-DE' | 'en-GB', continuous = false, interimResults = true
       │         onend → final transcript (string)
       │    └─ MemoService.dictate(text)  POST /api/v1/memo/dictate {transcript}
       └─ else
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
  ([`config/routes.rb`](../config/routes.rb)). `suggestions` and `dismiss_suggestion` sit beside
  it but play no part in dictation.
- **Language selection.** The client picks the recogniser language with `speechTag()`
  ([`speech.service.ts:28`](../frontend/src/app/core/services/speech.service.ts)): `de` maps to
  `de-DE`, and everything else maps to `en-GB`. The input is `translate.currentLang()`, which is
  the UI language chosen by
  [`LocaleService.initial()`](../frontend/src/app/core/services/locale.service.ts): the saved
  choice, else `navigator.language`, else the default. The same value goes to the server as
  `X-Locale` ([`locale.interceptor.ts`](../frontend/src/app/core/interceptors/locale.interceptor.ts)),
  where it sets `I18n.locale`
  ([`application_controller.rb`](../app/controllers/application_controller.rb) `set_locale`).
  **On the memo path the server does nothing with it.**
- **Who does the speech-to-text.**
  - **Browser path:** the browser's Web Speech API, free to us.
  - **Server path:** `gpt-4o-mini-transcribe` or Groq's `whisper-large-v3-turbo`
    (`Ai::Config::DEFAULT_TRANSCRIBE`), via [`Ai::Client#transcribe`](../app/services/ai/client.rb).
    The multipart body carries **only** `model` and `file` (`post_multipart`).
- **No model call on the browser path.** This is deliberate (comment at
  `memo_items_controller.rb:98`). The alpha keeps that rule as the default.

### How capture's voice path differs

[`CapturesController#from_voice`](../app/controllers/api/v1/captures_controller.rb) (`:81`) uses
the same `SpeechService` and `Ai::Transcriber`, but parses through `lines_from` (`:122`):

1. [`Text::Splitter`](../app/services/text/splitter.rb) splits on the same separators.
2. Each part goes to `ProductAlias.lookup`.
3. Only the parts the dictionary does not know reach `Ai::TextReader` (`gpt-5-nano`).

Capture also enforces `MAX_AUDIO_BYTES`, `MAX_TEXT_CHARS` and the capture budget. **The memo
`dictate` action enforces none of these.**

---

## 15.2 Why it fails

### 15.2.1 The stop button discards the words in progress ✅

`Memo.stopDictation()` calls `this.speech.cancel()` on the recognition path (`memo.ts:147`), and
`cancel()` calls `recognition.abort()` (`speech.service.ts:160`). `Capture.stopVoice()` does the
same (`capture.ts:272`).

- **What the spec says.** `abort()` is "a request to immediately stop listening and stop
  recognizing and do not return any information". By contrast, `stop()` tries "to return a result
  using just the audio that it has already received" ([Web Speech API spec](https://webaudio.github.io/web-speech-api/)).
- **What Chrome does.** In Chromium's renderer, `abort()` posts only an `end` event; an `aborted`
  error is raised only on an on-device connection error
  ([`speech_recognition.cc`](https://chromium.googlesource.com/chromium/src/+/main/third_party/blink/renderer/modules/speech/speech_recognition.cc)).
  The browser side's `AbortSilently()` passes error code `kNone`, and `Abort()` skips
  `OnRecognitionError` for `kNone`
  ([`speech_recognizer_impl.cc`](https://chromium.googlesource.com/chromium/src/+/main/content/browser/speech/speech_recognizer_impl.cc)).
  I could not find which handler the state machine maps `EVENT_ABORT` to, so "no error event"
  is the likely reading, not a confirmed one ❓.
- **The effect in our code.** `onend` emits `finalText`, which holds only results already marked
  final. Words still being recognised are lost. If none were final yet, `text` is empty and
  `if (text)` sends nothing. So the user taps stop and **nothing happens, with no message**.

A run in the in-app browser (Chromium 156) could not settle this, because microphone access is
blocked there: it fired `error: not-allowed`, then `end` 🧪.

### 15.2.2 Recognition ends at the first pause, and `continuous` does not help on Android ✅

- **Our setting.** `recognition.continuous = false` (`speech.service.ts:80`). The spec default is
  also `false`. With `true`, the user agent "must return zero or more final results representing
  multiple consecutive recognitions" ([spec](https://webaudio.github.io/web-speech-api/)).
- **Android Chrome.** MDN's browser-compat-data marks `continuous` on Chrome Android as **not
  implemented**: "The property can be set, but has no effect" (crbug 41297427,
  [`api/SpeechRecognition.json`](https://github.com/mdn/browser-compat-data/blob/main/api/SpeechRecognition.json)).
  So on Android the only way to keep listening across pauses is to start again when `end` fires.
- **Safari.** `continuous` is supported from Safari 17. Safari 14.1–16 was a partial
  implementation that "returns multiple results when set to `false`" (same source).
- **Android result quirks ⚠️.** Several developers report that Android Chrome returns duplicated
  or differently-flagged results compared with desktop:
  - [Stack Overflow #35112561](https://stackoverflow.com/questions/35112561)
  - a [2018 W3C public-speech-api post](https://lists.w3.org/Archives/Public/public-speech-api/2018Feb/0001.html)
  - [vueuse PR #3891](https://github.com/vueuse/vueuse/issues/3891), "results differ on mobile and desktop"

  These are reports, not confirmed behaviour. The plan does not depend on them: it rebuilds the
  transcript from `event.results` on every event, which is correct under the spec either way.

### 15.2.3 The splitter needs punctuation the recogniser does not produce 🧪 ✅

- **No punctuation by default ✅.** Chrome added an opt-in `unspokenPunctuation` attribute whose
  default is `false`: "no punctuation will be inserted automatically"
  ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/SpeechRecognition/unspokenPunctuation)).
- **Our splitter.** `extract_names` splits only on `,`, `;`, newlines, "and", "und" and "plus". It
  then strips one leading verb from a fixed list of four (`memo_items_controller.rb:106`).

Measured with `AI_MODE=stub bin/rails runner` against the dev dictionary (76 shared aliases) 🧪:

| Transcript | Memo today (`extract_names`) | Capture today (`Text::Splitter`) |
|---|---|---|
| `I want to buy bread milk eggs` | `["I want to buy bread milk eggs"]` (1 line) | `Milk` only, bread and eggs silently lost |
| `I want to buy bread, milk, eggs` | `["I want to buy bread", "milk", "eggs"]` | `Bread, Milk, Eggs` |
| `bread milk and eggs` | `["bread milk", "eggs"]` | `Milk, Eggs` |
| `ich brauche Brot Milch und Eier` | `["ich brauche Brot Milch", "Eier"]` | `Milch, Eier` |
| `Ich möchte Brot, Milch und Eier kaufen` | `["Ich möchte Brot", "Milch", "Eier kaufen"]` | `Brot, Milch, Eier` |
| `wir brauchen noch Butter Käse und zwei Gurken` | `["wir brauchen noch Butter Käse", "zwei Gurken"]` | `Butter, Salatgurke` ("Käse" lost) |
| `get some milk and also bananas` | `["some milk", "also bananas"]` | `Milk, Bananen` |

Two findings follow:

- **Memo.** The splitter only works when commas are present. Filler phrases end up inside the
  item name.
- **Capture has a silent data-loss bug.** A chunk holding several foods goes whole to
  `ProductAlias.lookup`. `token_match` (`product_alias.rb:67`) returns the **single** best entry,
  so the other foods vanish without reaching the model. That contradicts the comment on
  `parse_unknown`, which cites doc 4 §4.4 rule 4.

### 15.2.4 German: the language follows the UI, not the speaker 🧪 ✅

- **The tag is fixed to the UI language 🧪.** The recogniser is told `de-DE` only when the UI is
  German. Nothing lets the user pick a different speech language without switching the whole UI
  in Settings. Web Speech takes one `lang` per session.
- **The server path sends no language 🧪.** OpenAI documents `language` as "The language of the
  input audio", and says supplying an ISO-639-1 code "will improve accuracy and latency" ✅
  ([API reference](https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create)).
  Groq's docs say the same ✅ ([Groq](https://console.groq.com/docs/speech-to-text)). We send
  neither a language nor a prompt.
- **iOS recordings are mislabelled ✅.** WebKit's MediaRecorder writes MP4 with AAC audio
  ([WebKit blog](https://webkit.org/blog/11353/mediarecorder-api/)). Our code labels the blob
  `audio/webm` and names the file `memo.webm` (`speech.service.ts:152`, `memo.service.ts`). Both
  OpenAI and Groq accept `mp4` and `m4a`, so the right label costs nothing. Whether the wrong label
  breaks transcription today is untested ❓.
- **Who actually reaches the paid path ✅.** Per [MDN compat data](https://github.com/mdn/browser-compat-data/blob/main/api/SpeechRecognition.json):

  | Browser | SpeechRecognition |
  |---|---|
  | Chrome, desktop and Android | Yes (prefixed from 33, unprefixed from 139) |
  | Safari and iOS Safari | Yes, prefixed `webkit` from 14.1 |
  | Firefox desktop | Yes, from 160 |
  | Firefox Android | No |

  Safari's recogniser is the Siri engine and is available only if Siri is enabled
  ([WebKit, Safari 14.1](https://webkit.org/blog/11648/new-webkit-features-in-safari-14-1/)).
  So the recording path today serves mainly **Firefox Android** and **iPhones with Siri off**.
  Doc 14 §14.2's "only on iOS" is out of date.
- **iOS home-screen apps ❓.** In 2021 a WebKit engineer wrote that the API "is not available in
  SafariViewController and web apps added to Home Screen for now". The bug is RESOLVED LATER and
  its last comment (2025-03-01) asks for an update ([WebKit bug 225298](https://bugs.webkit.org/show_bug.cgi?id=225298)).
  Current behaviour is unverified. If the constructor is absent there, our code already falls back
  to recording; if it is present but fails, we show "no mic" and do not fall back.

### 15.2.5 A correction to doc 14 on privacy ✅

Doc 14 §14.2 says "Chrome and Android do speech recognition **on the device**". By default they
do not.

- **Chrome sends audio to Google.** Chromium's network engine posts audio to
  `https://www.google.com/speech-api/full-duplex/v1`
  ([source](https://chromium.googlesource.com/chromium/src/+/main/content/browser/speech/network_speech_recognition_engine_impl.cc)).
  A Chrome engineer wrote in 2025 that "Chrome is also moving away from cloud-based recognition
  and plans to phase it out over time"
  ([W3C list](https://lists.w3.org/Archives/Public/public-webapps-github/2025Apr/0450.html)).
- **On-device mode exists, but not on phones.** `processLocally`, `available()` and `install()`
  ship in Chrome **desktop** 139 and are **not** implemented on Chrome Android or Safari
  ([MDN compat data](https://github.com/mdn/browser-compat-data/blob/main/api/SpeechRecognition.json)).
  A Chrome engineer put language packs at "~60MB" each
  ([blink-dev intent](https://groups.google.com/a/chromium.org/g/blink-dev/c/VNOok2dbmHM)).

The cost to us is still zero. Doc 12's data-residency story should not claim the audio stays on
the phone.

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

A memo line does not have to be food, and the dictionary is food-only. Unknown words have to
survive as their own line.

---

## 15.4 Options, by phase

Unit of cost: **one dictation of 15 s**, as in doc 14. Every price below is from the vendor's own
page, checked 2026-11-17.

| Vendor price ✅ | Source |
|---|---|
| OpenAI `gpt-4o-mini-transcribe` $0.003/min (estimated; billed as $1.25 / $5.00 per 1M tokens) | [OpenAI pricing](https://developers.openai.com/api/docs/pricing) |
| OpenAI `gpt-4o-transcribe` $0.006/min | same |
| OpenAI `gpt-5-nano` $0.05 / $0.40 per 1M tokens | same |
| Groq `whisper-large-v3-turbo` $0.04/hour, 10 s minimum per request | [Groq speech-to-text](https://console.groq.com/docs/speech-to-text) |
| Mistral Voxtral Mini Transcribe V2 (batch) $0.003/min; Voxtral Realtime $0.006/min; German among its 13 languages | [Mistral, 2026-02-04](https://mistral.ai/news/voxtral-transcribe-2), [docs](https://docs.mistral.ai/capabilities/audio_transcription) |
| Fly performance-1x 2 GB $33.00/month; extra RAM $6.00/GB/month; per-second billing while running | [Fly pricing](https://docs.fly.io/about/pricing) |

### Alpha: the browser's recogniser, used properly, plus a free parser

| | |
|---|---|
| **What** | Web Speech, single-shot (`continuous = false`), started and stopped by a hold-to-talk / tap-to-toggle mic (§15.8); `stop()` not `abort()`; a DE/EN speech-language toggle. The server splits with a dictionary-driven segmenter (§15.6 step 5). No continuous listening in the alpha. |
| **Cost per use** | **$0** wherever SpeechRecognition exists. **$0.00075** on the recording fallback (0.25 min × $0.003). |
| **Latency** | Words appear live through interim results; one server round trip after stop, with no model call. |
| **Platform support ✅** | Chrome desktop and Android, Safari and iOS Safari (Siri must be on), and Firefox desktop 160+. Firefox Android takes the recording path. iOS home-screen behaviour is unverified ❓. |
| **Accuracy** | Recogniser accuracy in German and English is not published by Google or Apple, so we must measure it on our own sentences. The parser is limited by the dictionary (76 shared aliases + household history today). |
| **Complexity** | No new dependency, no new infrastructure. |
| **Optional extra ✅** | `unspokenPunctuation = true` makes the engine insert commas. It is in Chrome 151 per MDN compat data. The intent to ship says "Shipping on desktop" while the compat data marks Chrome Android as matching desktop: **conflicting**, so test on a phone ❓. Not in Safari. Harmless to set; the segmenter does not depend on it. |

### Beta: one cheap server transcription where the browser falls short

Send audio with `language` and a list-shaped `prompt`, for example "Einkaufsliste: Milch, Brot,
Eier, Klopapier." OpenAI's guide lists "Preserving punctuation, capitalization, and filler words"
as a use of prompting, and says `gpt-4o-mini-transcribe` supports prompts ✅
([guide](https://developers.openai.com/api/docs/guides/speech-to-text)). Groq supports `prompt`,
up to 224 tokens ✅. Mistral documents "context biasing" with custom vocabulary for Voxtral Mini
Transcribe V2 ✅. Whether a list-shaped prompt reliably yields comma-separated output for our
sentences is **untested** ❓, so it goes in the evaluation set (§15.7).

| Provider / model | **Per 15 s use** | Notes |
|---|---|---|
| Groq `whisper-large-v3-turbo` (already a provider in `Ai::Config`) | **$0.000167** | Billed for 15 s, above the 10 s minimum. |
| OpenAI `gpt-4o-mini-transcribe` (already the default) | **$0.00075** | |
| Mistral Voxtral Mini Transcribe V2 | **$0.00075** | Needs a new provider entry. The announcement page does not state EU hosting, so residency is unverified ❓. |
| OpenAI `gpt-4o-transcribe` | $0.0015 | Only if mini proves too weak. |

- **Caps.** Max 30 s per clip, capture's `MAX_AUDIO_BYTES` on memo too, a per-household daily
  cap, and the existing `Ai::Budget`.
- **Volume.** At 13 dictations a month a household costs 13 × $0.00075 ≈ **$0.0098/month** on
  OpenAI mini, or 13 × $0.000167 ≈ **$0.0022/month** on Groq.

### v1: on-device first, self-hosted only where it pays

| Option | Per use | Verified facts | Verdict |
|---|---|---|---|
| **Native shell recogniser** | $0 | iOS: `SFSpeechRecognitionRequest.requiresOnDeviceRecognition`, "whether a request must keep its audio data on the device", iOS 13+ ✅ ([Apple](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)). Android: `SpeechRecognizer.createOnDeviceSpeechRecognizer`, API 31+, plus language detection limited to allowed languages, API 34+ ✅ ([Android](https://developer.android.com/reference/android/speech/SpeechRecognizer)). | **Best v1 answer.** It comes with the shell doc 5 plans for push. Android's language detection could replace the DE/EN toggle. |
| **Chrome on-device Web Speech** | $0 | Chrome desktop 139+ only; not Android, not Safari ✅. | Helps desktop only. Low priority for a phone-first app. |
| **whisper.cpp on the existing app machine** | ≈ $0 marginal | Today's VM: `shared-cpu-1x`, 512 MB ([`fly.toml`](../fly.toml)). whisper.cpp memory ✅ ([README](https://github.com/ggml-org/whisper.cpp)): tiny ~273 MB, base ~388 MB, small ~852 MB. Small therefore needs the VM raised by at least 1 GB: **+$6.00/month** per GB ✅. Speed on a shared vCPU is **unmeasured** ❓. | The cheapest real self-host, but only after measuring its latency. |
| **Separate ASR machine on Fly** | Depends on idle time | performance-1x is $33.00/month ≈ **$0.00075 per minute running** ($33 ÷ 730 h ÷ 60). Once woken it runs until the proxy finds it idle; Fly documents only that the stop loop runs "every few minutes", with no exact figure ✅ ([Fly autostop](https://docs.fly.io/reference/fly-proxy-autostop-autostart/)). **Each wake therefore costs at least one OpenAI-mini transcription per idle minute.** | **Do not build** at our volume. |
| **Vosk in the browser** | $0 | `vosk-model-small-de-0.15`: 45 MB, WER 13.75 % (Tuda-de) and 30.67 % (podcast). `vosk-model-small-en-us-0.15`: 40 MB, WER 9.85 % (LibriSpeech clean). Apache 2.0. "Most small model allow dynamic vocabulary reconfiguration" ✅ ([Vosk models](https://alphacephei.com/vosk/models)). The vosk-browser package could not be checked (npm and GitHub pages returned 403/404) ❓. | Prototype only. |
| **Whisper in the browser or on the server: accuracy reference** | $0 / see above | Whisper paper, FLEURS WER ✅ ([Radford et al., Table 13](https://cdn.openai.com/papers/whisper.pdf)) — German: tiny 27.8, base 17.9, small 10.2, medium 6.5, large-v2 4.5. English: tiny 12.4, base 8.9, small 6.1, medium 4.4, large-v2 4.2. FLEURS is read speech, not a noisy shop. | German WER relative to `large-v2`: small 2.3×, base 4.0×, tiny 6.2× (computed from the table). Browser download sizes for transformers.js builds are unverified ❓. |
| **GPU** | — | Not on a machine that sleeps. | Out of scope. |

The v1 picture from these numbers: self-hosted server ASR does not beat Groq's $0.04/hour at our
volume. The parts we own and that pay are the **parser** (from the alpha) and **on-device
recognition** through the native shell.

---

## 15.5 Cost per use, summary

All figures are derived from the vendor prices above.

| Phase | Common path | Fallback path | Per household / month (13 dictations) |
|---|---|---|---|
| **Alpha** | **$0** | $0.00075 (OpenAI mini) | $0 to ≈ $0.0098 |
| **Beta** | $0 where the browser recogniser works | $0.000167 (Groq) to $0.00075 (OpenAI mini, Voxtral) | ≈ $0.0022 to ≈ $0.0098 |
| **v1** | **$0** (native on-device) | as beta, or whisper.cpp on the app VM at +$6/GB/month fixed | ≈ $0 |

---

## 15.6 Alpha recommendation and implementation plan

**Recommendation.** The alpha's goal is that **German and English work equally well**. Keep the
browser recogniser, single-shot, and fix how we drive it. Let the user choose the speech
language. Drive the mic with hold-to-talk and tap-to-toggle (§15.8). Turn the transcript into
lines with a free segmenter shared by memo and capture. Add no new provider and no new
infrastructure.

**Deferred, not in the alpha:** continuous listening, i.e. restarting recognition on `end` across
pauses. §15.2.2 records why it would need a restart loop on Android. Hold-to-talk makes it
unnecessary for now, because each hold is one short single-shot session.

1. **Stop means stop** (`speech.service.ts`, `memo.ts:145`, `capture.ts:272`). Add
   `SpeechService.finish()`, which calls `recognition.stop()`, per the spec semantics in §15.2.1.
   Keep `cancel()` → `abort()` for navigating away and for a cancelled hold. Treat `no-speech` and
   `aborted` as an empty result, not a "no mic" error. Rebuild the final text from
   `event.results` rather than appending.
2. **Hold to talk, tap to toggle** (`memo.html`, `memo.ts`, `memo.scss`); the interaction is
   specified in §15.8.4. Keep `continuous = false`.
3. **Speech language toggle** (`memo.html`, `speech.service.ts:28`). Add a `DE | EN` chip beside
   the mic, defaulting to the UI locale and remembered in `localStorage` (try/catch, like
   `LocaleService`). Send it as `lang` with `dictate` and `dictateAudio`.
4. **Server transcription gets a hint** (`ai/client.rb` `post_multipart`, `ai/transcriber.rb`).
   Pass `language` and a list-shaped `prompt` in that language. Label recordings with
   `recorder.mimeType` and a matching file extension (`.m4a` or `.mp4` on Safari ✅). If
   recognition errors with `service-not-allowed` or `not-allowed` while a constructor exists, fall
   back to recording.
5. **Segmenter** (new `Text::Segmenter`, used by `Text::Splitter` and replacing `extract_names`):
   1. Normalise with `ProductAlias.normalize_key`.
   2. Split on the existing separators plus "also/auch/sowie/dann/noch/then".
   3. Strip filler from both languages, whatever the toggle says. These lists are a starting
      point and must be reviewed by a native speaker and grown from the evaluation set (§15.7).
   4. Within each chunk, take the **longest exact dictionary match of up to 3 tokens**, left to
      right. The dictionary is shared aliases, household aliases, the household's past memo
      names and `Memo::Suggester::STAPLES`. Each run of unknown tokens becomes its own line.
   5. Treat number words before a match as its quantity.

   This also fixes capture's silent loss (§15.2.3), because `lines_from` gets one part per food.
6. **Optional leftover fallback**, off by default. A chunk with no dictionary hit and ≥ 4 tokens
   goes to `Ai::TextReader` under the configured but unused `memo_parse` purpose. Log the
   would-have-fired count either way.
7. **Caps on memo dictate** (`memo_items_controller.rb:27`). Apply capture's `MAX_AUDIO_BYTES`,
   `MAX_TEXT_CHARS` and budget check.
8. **Tests and evaluation** (§15.7):
   - Request specs with the §15.2.3 and §15.3 sentences, under `AI_MODE=stub`.
   - A unit spec for `Text::Segmenter`, including the "no word silently dropped" invariant.
   - A frontend spec for `SpeechService` with a fake recogniser.
   - A manual pass on a real Android phone and an iPhone, both in the browser tab and from the
     home screen, to settle every ❓ above.

**Done when:**
- the §15.3 sentences produce the expected lines with the speech toggle on DE and on EN, whatever
  the UI language, on Android Chrome and iOS Safari;
- a hold for one word ("Milch", "eggs") adds exactly that line;
- releasing or tapping stop never loses words, and a cancelled hold adds nothing;
- the cost screen shows zero billed calls for a browser-path dictation.

---

## 15.7 Quality: how we will know it works in both languages, and what libraries can help

No algorithm here is assumed to work in German or English. It is measured.

**Evaluation set.**
- Collect real transcripts, exactly as Chrome and iOS return them, from the Berlin concierge
  test: German, English and mixed lists, each with the expected lines.
- Report line recall, line precision and exact-list match per language in CI, and gate merges on
  them.
- Add one property test: every input word ends up in a line or is explicitly classed as filler, a
  separator or a number. That would have caught capture's silent loss.

**Production signal.** A dictated line deleted or renamed within minutes is an error signal,
tracked per language. The memo already records updates and deletes.

**Libraries, tested here** 🧪 (Python 3.14 venv in the scratchpad; Ruby 3.4.10):

| Library | What it is | Result on our sentences | Verdict |
|---|---|---|---|
| spaCy 3.8.18, `en_core_web_sm` / `de_core_news_sm` 3.8.0, noun chunks | General NLP parser | English: "I want to buy bread milk eggs" → one chunk `bread milk eggs`; "milk toilet paper and…" → `milk toilet paper`. German with capitalised nouns: `Brot`, `Milch`, `Eier` separately. German **lower-case** (`brot milch und eier`) → `brot milch`, `eier`. | **Does not split unpunctuated English lists**, and German works only when nouns are capitalised. Not a substitute for the segmenter. |
| Snowball German/English stemmer (official `snowballstemmer` 3.1.1; Ruby `ruby-stemmer` 3.0.0 wraps libstemmer) | Plural and inflection folding | Matches gurke/gurken, apfel/äpfel, tomate/tomaten, zwiebel/zwiebeln, banane/bananen, egg/eggs, tomato/tomatoes, cherry/cherries. **Does not match ei/eier or loaf/loaves.** Folds umlauts (`käse` → `kas`), as the algorithm specifies ✅ ([Snowball German](https://snowballstem.org/algorithms/german/stemmer.html)). Both packages give identical stems. | Useful as a second matching pass, with the irregulars (Ei/Eier) kept in the dictionary. `ruby-stemmer`'s last release is 2020-10-16 ✅ ([RubyGems](https://rubygems.org/gems/ruby-stemmer)); it builds and runs on Ruby 3.4.10 here 🧪. |
| `oliverguhr/fullstop-punctuation-multilang-large` | Restores punctuation | Model card ✅ ([Hugging Face](https://huggingface.co/oliverguhr/fullstop-punctuation-multilang-large)): EN/DE/FR/IT; 0.6B parameters (XLM-RoBERTa); MIT; comma F1 **0.819 EN, 0.945 DE**. Not run here. | Too large for our 512 MB VM. The comma F1 on our list-shaped sentences is unmeasured ❓. |
| LLM (`gpt-5-nano`) | General | Not run here. | The quality reference for the evaluation set, offline. Its use at request time is the flagged fallback in step 6. |

Not verified, so not relied on ❓:
- the size of the Open Food Facts ingredients taxonomy and its German/English coverage (the wiki
  gives no count; counting requires downloading the taxonomy file);
- transformers.js Whisper download sizes;
- whisper.cpp speed on Fly's shared CPU.

---

## 15.8 Hold to talk: what users already do, and how the mic should behave

The request was to make voice input flexible enough to work item by item: hold the mic, say
"Milch", let go. This section checks that pattern against what people use today and against
platform and accessibility rules, before any design is fixed.

### 15.8.1 People already know two voice gestures, and use them for different jobs ✅

| Job | Convention | Source |
|---|---|---|
| **Voice message** (short, sent as audio) | **Press and hold** the mic, speak, **release to send**. **Slide left to cancel.** | Telegram's documentation: "tap and hold the microphone icon", released to send, "Sliding to the left while recording cancels" ([Telegram](https://core.telegram.org/blackberry/chat-voice)). WhatsApp's Help Center describes the same hold, release and slide-to-cancel steps ([WhatsApp FAQ](https://faq.whatsapp.com/657157755756612/?cms_platform=android); the page would not render for fetching, so this is from WhatsApp's own help text shown in search results). |
| **Dictation** (speech becomes text) | **Tap** the mic to start; tap again, say "stop dictation", or wait 30 s of silence to stop. | Apple, "Dictate text on iPhone" ([Apple Support](https://support.apple.com/guide/iphone/dictate-text-iph2c0651d2/ios)). Gboard: "tap Microphone" ([Gboard Help](https://support.google.com/gboard/answer/2781851?hl=en&co=GENIE.Platform%3DAndroid)). |

Release-to-send is not universal:
- **Google Messages:** "Press and hold Mic", then "Tap Send"
  ([Messages Help](https://support.google.com/messages/answer/6159880)).
- **Google Chat on iPhone:** "tap the mic", then the stop button, then "Send"
  ([Chat Help](https://support.google.com/chat/answer/14763931?hl=en&co=GENIE.Platform%3DiOS)).

So both gestures are familiar, and neither is universal.

### 15.8.2 How common voice input is, in Germany specifically ✅

- **Bitkom, 27 March 2024** (telephone survey, representative, 1,005 people aged 16+, of whom 773
  smartphone users) ([Bitkom](https://www.bitkom.org/Presse/Presseinformation/Mehrheit-erhaelt-gerne-Sprachnachrichten)):
  - **41 %** of smartphone users like sending voice messages.
  - By age: **53 %** at 16–29, 46 % at 30–49, 35 % at 50–64, **28 %** at 65+.
  - **75 %** say long voice messages annoy them.
- **Bitkom, 14 November 2023** (representative survey, 1,159 people aged 16+): 558 of the
  respondents use voice assistants
  ([Bitkom](https://www.bitkom.org/Presse/Presseinformation/Wetter-Kochrezepte-Witze-Einsatz-digitale-Sprachassistenten)).
- **Worldwide scale:** Meta reported 7 billion WhatsApp voice messages sent daily on average
  ([Meta, 30 March 2022](https://about.fb.com/news/2022/03/new-voice-message-features-on-whatsapp/)).
  That is the latest official figure found.

What this supports: the hold gesture is widely practised, and short voice input is the norm.
What it does **not** show: how many people would hold a mic to build a *shopping list*. No study
of that was found ❓, and §15.8.5 measures it.

### 15.8.3 What the rules say about press-and-hold ✅

- **Apple HIG, Gestures.** The standard meaning of touch and hold is "Reveal additional controls or
  functionality". A custom gesture must be discoverable and "Not the only way to perform an
  important action". And: "Don't assume that people can use a specific gesture to perform a given
  task." ([Apple HIG](https://developer.apple.com/design/human-interface-guidelines/gestures))
- **WCAG 2.2, 2.5.2 Pointer Cancellation (Level A).** One allowed form is "Completion of the
  function is on the up-event, and a mechanism is available to abort the function"
  ([W3C](https://www.w3.org/WAI/WCAG22/Understanding/pointer-cancellation.html)). Hold-to-talk
  complies if lines are added **on release** and a hold can be cancelled.
- **WCAG 2.2, 2.5.1 Pointer Gestures (Level A).** Long press and click-and-hold count as
  single-pointer methods, not path-based gestures. A slide whose direction or length must be
  recognised is path-based and needs an alternative
  ([W3C](https://www.w3.org/WAI/WCAG22/Understanding/pointer-gestures.html)). So a "slide left to
  cancel" must not be the only way to cancel.
- **Research on discoverability.** In a peer-reviewed study, Arleth, Damkjær and Knoche write that
  "the affordance of a long tap on a button is often hidden in touch interfaces". Their experiment
  found "no clear tendencies" on when a hint should appear (before, during or after the gesture)
  (ArtsIT/DLI 2019, Springer 2020, [doi:10.1007/978-3-030-53294-9_20](https://doi.org/10.1007/978-3-030-53294-9_20)).
  That is a single study, so it is a reason to show a visible hint, not proof of a hint design.

### 15.8.4 The interaction this supports

One mic button with two ways in, so neither gesture is "the only way":

| Gesture | What happens | Why |
|---|---|---|
| **Press and hold** | Recognition starts on press. The "listening" state shows only once `audiostart` fires, which the spec defines as "the user agent has started to capture audio" ✅. **Release** calls `stop()`, and the lines are added. | The voice-message convention (§15.8.1). It completes on the up-event, as WCAG 2.5.2 allows. One hold is one short single-shot session, so no continuous mode is needed. |
| **Tap** (press shorter than a threshold) | Toggles listening on. It ends when the recogniser ends by itself or on a second tap. | The dictation convention. It is the alternative for anyone who cannot hold, as the Apple HIG asks. |
| **Cancel** | Release outside the button, **or** tap a visible ✕ while listening. Calls `abort()`; nothing is added. | WCAG 2.5.2's abort mechanism. The ✕ is the single-pointer alternative WCAG 2.5.1 requires for any slide. |
| **After each release** | The new lines appear as chips with an undo. | Mistakes are cheap to fix. Undo uses the existing `destroy`. |
| **Hint** | A visible line under the mic, e.g. "Halten und sprechen · Tippen für Liste" / "Hold and speak · tap for a list", until the user has used the mic a few times. | Long press is a hidden affordance (§15.8.3). |
| **Language** | The DE/EN chip beside the mic, from §15.6 step 3. | The alpha's main goal. |

**Browser details that need care.**
- **iOS callout ✅.** On iOS, Safari shows a callout when a target is touched and held, and
  `-webkit-touch-callout: none` disables it
  ([MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/-webkit-touch-callout)).
  The button also needs `user-select: none`.
- **Restarting too fast ✅.** Calling `start()` while a session is still running throws
  `InvalidStateError` ([spec](https://webaudio.github.io/web-speech-api/)). A quick second hold
  must wait for the previous `end`.
- **Not verified ❓, to test on devices before release:**
  - whether the first-use microphone permission prompt breaks a hold. If it does, ask for
    permission on the first tap, with an explanation;
  - how long after press the first words are captured, i.e. whether the start of a word gets
    clipped on Android Chrome and iOS Safari;
  - the right tap-versus-hold threshold;
  - haptic feedback. `navigator.vibrate` support on iOS was not checked.

### 15.8.5 How we find out whether people actually use it

The evidence above shows the gesture is familiar. It does not show it suits a shopping list. In the
Berlin concierge test, log per dictation:

- hold or tap;
- duration;
- speech language and UI language;
- lines added;
- lines deleted or renamed within 5 minutes;
- cancels.

Then compare holds with taps, German with English, and the Bitkom age bands (28–53 % like voice
messages, §15.8.2). Ask five to eight households to think aloud while building a list, which shows
whether the hint is understood. Decide on the default gesture from those numbers, not from this
document.

---

### Sources

- **Code:**
  [`memo_items_controller.rb`](../app/controllers/api/v1/memo_items_controller.rb),
  [`captures_controller.rb`](../app/controllers/api/v1/captures_controller.rb),
  [`speech.service.ts`](../frontend/src/app/core/services/speech.service.ts),
  [`memo.ts`](../frontend/src/app/features/memo/memo.ts),
  [`memo.service.ts`](../frontend/src/app/core/services/memo.service.ts),
  [`locale.service.ts`](../frontend/src/app/core/services/locale.service.ts),
  [`text/splitter.rb`](../app/services/text/splitter.rb),
  [`product_alias.rb`](../app/models/product_alias.rb),
  [`ai/client.rb`](../app/services/ai/client.rb), [`ai/config.rb`](../app/services/ai/config.rb),
  [`ai/transcriber.rb`](../app/services/ai/transcriber.rb), [`fly.toml`](../fly.toml).
- **Specs and browser data:**
  [Web Speech API spec](https://webaudio.github.io/web-speech-api/) ·
  [MDN browser-compat-data, SpeechRecognition](https://github.com/mdn/browser-compat-data/blob/main/api/SpeechRecognition.json) ·
  [MDN `unspokenPunctuation`](https://developer.mozilla.org/en-US/docs/Web/API/SpeechRecognition/unspokenPunctuation) ·
  [MDN, Using the Web Speech API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Speech_API/Using_the_Web_Speech_API) ·
  [Chromium `speech_recognition.cc`](https://chromium.googlesource.com/chromium/src/+/main/third_party/blink/renderer/modules/speech/speech_recognition.cc) ·
  [Chromium `speech_recognizer_impl.cc`](https://chromium.googlesource.com/chromium/src/+/main/content/browser/speech/speech_recognizer_impl.cc) ·
  [Chromium network speech engine](https://chromium.googlesource.com/chromium/src/+/main/content/browser/speech/network_speech_recognition_engine_impl.cc) ·
  [blink-dev: on-device Web Speech](https://groups.google.com/a/chromium.org/g/blink-dev/c/VNOok2dbmHM) ·
  [blink-dev: unspoken punctuation](https://groups.google.com/a/chromium.org/g/blink-dev/c/cD_-fohuHrs) ·
  [W3C list, Chrome moving off cloud recognition](https://lists.w3.org/Archives/Public/public-webapps-github/2025Apr/0450.html) ·
  [WebKit: Safari 14.1](https://webkit.org/blog/11648/new-webkit-features-in-safari-14-1/) ·
  [WebKit: MediaRecorder](https://webkit.org/blog/11353/mediarecorder-api/) ·
  [WebKit bug 225298](https://bugs.webkit.org/show_bug.cgi?id=225298).
- **Platforms:**
  [Apple `requiresOnDeviceRecognition`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition) ·
  [Android `SpeechRecognizer`](https://developer.android.com/reference/android/speech/SpeechRecognizer).
- **Vendors:**
  [OpenAI pricing](https://developers.openai.com/api/docs/pricing) ·
  [OpenAI transcription API](https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create) ·
  [OpenAI speech-to-text guide](https://developers.openai.com/api/docs/guides/speech-to-text) ·
  [Groq speech-to-text](https://console.groq.com/docs/speech-to-text) ·
  [Mistral Voxtral Transcribe 2](https://mistral.ai/news/voxtral-transcribe-2) ·
  [Mistral audio docs](https://docs.mistral.ai/capabilities/audio_transcription) ·
  [Fly pricing](https://docs.fly.io/about/pricing) ·
  [Fly autostop](https://docs.fly.io/reference/fly-proxy-autostop-autostart/).
- **Models and research:**
  [Whisper paper](https://cdn.openai.com/papers/whisper.pdf) ·
  [whisper.cpp](https://github.com/ggml-org/whisper.cpp) ·
  [Vosk models](https://alphacephei.com/vosk/models) ·
  [fullstop punctuation model](https://huggingface.co/oliverguhr/fullstop-punctuation-multilang-large) ·
  [Snowball German stemmer](https://snowballstem.org/algorithms/german/stemmer.html) ·
  [ruby-stemmer](https://rubygems.org/gems/ruby-stemmer).
- **Community reports (⚠️):**
  [Stack Overflow #35112561](https://stackoverflow.com/questions/35112561) ·
  [W3C public-speech-api, 2018](https://lists.w3.org/Archives/Public/public-speech-api/2018Feb/0001.html) ·
  [vueuse #3891](https://github.com/vueuse/vueuse/issues/3891).
