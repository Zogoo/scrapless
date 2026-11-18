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
>
> **LLM splitting, measured 2026-11-18 (§15.11):** `gpt-6-luna` costs about **$0.000064 per
> dictation**. It got 18 of 20 hard natural sentences right, where the segmenter got 3. Used
> only when the segmenter does not know every word, it got 149 of 152 cases right. It adds
> 1–2 s after release and needs a timeout with the segmenter as fallback. Also found:
> `gpt-5-nano` and `gpt-5-mini`, the app's OpenAI defaults, **shut down on 11 Dec 2026**.
>
> **Built for evaluation (§15.11.1):** `Memo::ListReader`, which uses the segmenter first and
> `gpt-6-luna` only when the segmenter is unsure. It has a 4 s deadline and falls back to the
> segmenter's lines. Run `script/dictation_eval/run.sh live` to measure it end to end.

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
| "milk toilet paper and something for Sunday" | Milk · toilet paper (a vague reminder is not a line; decided 2026-11-18) |
| "Milch, Klopapier, Brötchen" (English UI) | Milch · Klopapier · Brötchen |

A memo line does not have to be food (toilet paper), and the dictionary is food-only, so an
unknown item has to survive as its own line. A vague reminder ("something for Sunday") is not
an item and is left out (product decision, 2026-11-18). The segmenter cannot tell the two
apart, so it keeps both and reports itself unsure, and the model decides (§15.11.1).

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

## 15.9 What was built (branch `memo-dictation-alpha`)

Built in two passes. The second pass reworked the first after a review for narrow,
pattern-matched solutions; §15.10 lists what changed and why.

| Plan step | Where | Notes |
|---|---|---|
| 1. Stop means stop | `SpeechService.finish()` → `stop()`; `cancel()` → `abort()`, cancellation per session | `no-speech` and `aborted` end quietly. The transcript is rebuilt from the whole result list. Capture's stop uses `finish()` too. |
| 2. Hold to talk, tap to toggle | `memo.ts` `onMicDown`/`onMicUp`/`onMicPointerCancel`/`onMicClick` | A hold adds the lines on release; a tap listens until a second tap; release outside or the visible ✕ cancels; Enter or Space toggles. "One moment…" shows until `audiostart`. A hint shows for the first three uses. `continuous` stays `false`. |
| 3. Speech language | `SpeechService.speechLang`; the chip lists `environment.availableLocales`; recogniser tags in `core/speech-tags.ts` | The speech language defaults to the UI language and is sent as `lang` with every dictation. A language with no tag uses its own code, never another language. |
| 4. Server hint | `Ai::Transcriber` sends `language` and the prompt from `config/dictation/<locale>.yml` | Recordings carry their real MIME type. `service-not-allowed` switches the next press to recording. |
| 5. Segmenter | `Text::Segmenter` over `Text::Lexicon`, used by memo dictation and by capture's `Text::Splitter` | Details below. |
| 6. Leftover fallback | log only | A group of several words with no known item is logged as unresolved. **No model call was added.** |
| 7. Caps | `InputLimits`, shared by capture and memo | Text length, audio size, and paid transcriptions per kitchen per hour. |
| 8. Tests | `spec/fixtures/dictation/*.yml`, `segmenter_spec`, `learn_from_correction_spec`, `vocabulary_spec`, `memo_items_spec`, `client_spec`, `speech.service.spec.ts`, `memo.spec.ts` | 412 RSpec examples and 123 Vitest tests pass; RuboCop, Brakeman and bundler-audit are clean. |

**How the segmenter decides.** No word list lives in code:

- **Per-language data.** Separator words, filler at the start and end, spoken numbers, units,
  modifiers and the transcription prompt are in `config/dictation/<locale>.yml`, loaded for
  every locale in `config.i18n.available_locales` (`Dictation::Vocabulary`). All languages are
  used at once, because lists are mixed.
- **Known phrases** come from the shared dictionary, the suggester's staples, and per kitchen:
  - its aliases;
  - what it has bought;
  - lines a person typed or picked (never lines the mic wrote);
  - what it learned from corrections.
- **Longest known item phrase wins.** How many words to try is taken from the data, not a constant.
- **Attaching to an item.** Numbers, units and modifiers directly before an item belong to it
  ("2 Flaschen Bio Milch"). Other unknown words stay together as their own line. The earlier
  guessed rule ("up to two unknown words join the next item") was removed; "oat milk" is now
  one line only once the kitchen's data knows it.
- **Cost per request.** The shared lexicon is built once per process and rebuilt only when the
  shared dictionary changes, so a much larger dictionary costs one version query per request.
  The kitchen's own rows are bounded per source.

**Learning from corrections.** Each line just dictated shows as a chip. Tapping it lets the
person fix it, and `Memo::LearnFromCorrection` keeps the evidence (`VocabularyEntry`, per kitchen):
- the corrected name becomes an item phrase;
- words trimmed off either end become that kitchen's filler.

Words that are themselves known items are never learned as filler ("tortillas milch" →
"tortillas" means two glued items).

**Measured, not guessed.** Each dictation logs the gesture (`hold`/`tap`/`key`, from a fixed set),
the press duration, and the speech and UI languages. The 350 ms tap/hold threshold is a labelled
heuristic, to be tuned from those logs.

**How it is tested.**
- **Evaluation set:** `spec/fixtures/dictation/*.yml` holds `said` → `lines` cases per language.
  Adding a case is data. Today it holds the §15.3 acceptance sentences, to be replaced by
  concierge-test transcripts.
- **Generated lists:** for every locale, 200 random lists of real seeded dictionary entries,
  with random filler and separator words from that locale's data and no punctuation. Every item
  must come back alone.
- **Invariant:** random input never loses a word that is not known filler.
- **Consistency across stacks:** every app locale has dictation data, a UI translation file and
  a recogniser tag, and the frontend and backend locale lists match.

**Checked in the in-app browser 🧪** (Chromium, worktree servers, own SQLite file; a stand-in
recogniser, because the microphone is blocked there):

| Gesture | Speech language | Said | Result |
|---|---|---|---|
| Tap, tap | DE | "ich brauche Brot Milch und zwei Gurken" | **Brot · Milch · 2 Gurken**, with `de-DE` |
| Hold | EN | "toilet paper" | **Toilet paper**, with `en-GB` |
| Hold, release outside | — | — | Nothing added |
| Hold | DE | "ich hätt gern Hafermilch" | One line, corrected on the chip to "Hafermilch" |
| Hold | DE | "ich hätt gern Hafermilch und Brot" (said again later) | **Hafermilch · Brot**: the correction was learned |

**Still needs a real phone ❓:** the §15.8.4 list (permission prompt during a hold, first-word
clipping, the hold threshold), iOS Safari, Android Chrome, and the iOS home-screen app.

## 15.10 What the generality review changed, and what is still narrow

| Was narrow | Now |
|---|---|
| `'de' \| 'en'` retyped in five places | The app's locale list (`environment.availableLocales`, `config.i18n.available_locales`), with specs that keep them and their data in step |
| Filler, numbers, units and separators as constants in code | Per-language data files plus per-kitchen learned phrases |
| A guessed "two unknown words attach" threshold | Removed. Only data-marked numbers, units and modifiers attach |
| Learning from the mic's own output, guarded by a special case | Learning only from what a person typed, picked or corrected |
| A fixed maximum phrase length of 3 | Taken from the longest phrase in the data |
| Dictionary loaded in full on every request | Shared part cached per process, keyed on the dictionary's version |
| Tests that restated the rules | An evaluation set as data, generated lists from the real dictionary, and an invariant |
| Limits borrowed from another controller | `InputLimits` |
| Hold threshold presented as a value | Labelled heuristic, logged per dictation |

**Still narrow, not changed in this pass:**

- **Inflection.** Without stemming, "Gurke" and "Gurken" are different phrases until a kitchen
  teaches it or the dictionary lists both. The maintained option is the official Snowball C
  library: Debian trixie packages it (`libstemmer0d` 2.2.0 ✅,
  [packages.debian.org](https://packages.debian.org/search?keywords=libstemmer&searchon=names&suite=stable&section=all)),
  and Homebrew has a `snowball` formula. Using it means a native system library in Docker,
  development and CI, called through Ruby's built-in Fiddle. The Ruby gem `ruby-stemmer` is
  **archived** (since 12 May 2022, [GitHub](https://github.com/aurelian/ruby-stemmer)), so it
  was not added. A decision for the team.
- **Non-Latin letters.** `ProductAlias.normalize_key` keeps only a–z, digits and äöüß, so a
  language with other letters (é, ñ, ł) would lose characters. Widening it means
  re-normalising stored dictionary keys, which is a migration of its own.
- **Staples.** `Memo::Suggester::STAPLES` hardcodes one English and one German word per staple.
- **Dictionary size.** The shared dictionary has 76 entries. Seeding it from a maintained
  multilingual food dataset is the biggest quality lever left. Open Food Facts' size and
  licensing must be checked first (doc 12).
- **Filler lists.** The data files are curated starting points; coverage grows with learning and
  the evaluation set.

---

## 15.11 An LLM as the splitter: measured cost and quality 🧪

**Question.** What does it cost to send the transcript to a GPT model and get back only the clean
items, and is it better than `Text::Segmenter`?

> **Answer, from one run on 2026-11-18.**
> - **Cost: about $0.000064 per dictation** with `gpt-6-luna` (reasoning effort `none`). At
>   13 dictations a household a month (§15.4) that is **≈ $0.0008 a month**. It is about a
>   twelfth of one 15 s recording fallback ($0.00075, §15.5).
> - **Quality: much better on natural speech, worse on clean lists.** On 20 hard sentences the
>   model got **18** lists exactly right and the segmenter **3**. On clean dictionary lists
>   the segmenter was right every time and the model was not.
> - **Best measured: segmenter first, model only when the segmenter did not know every word.**
>   That got **149 of 152** cases right and called the model on 22 of them.
> - **The price is latency:** a median of 1.5 s and a 90th percentile of 2.3 s from this
>   machine, after the finger is lifted. Also, 4 of 760 calls got no answer within 60 s.

### Setup

- **Cases (152):** the 12 sentences of `spec/fixtures/dictation`, plus 20 hand-written hard
  sentences, plus 60 generated lists per locale built from the seeded dictionary with that
  language's filler and separators (the generator from `segmenter_spec.rb`, seed 42).
  - The hard sentences contain self-corrections ("Milch nee warte Hafermilch"), compounds the
    dictionary lacks ("peanut butter", "chicken thighs"), quantities with units, words for
    where and why ("at the bakery", "für den Kuchen"), non-food items, unknown foods
    ("Yuzu Tahini und Gochujang") and an empty request.
  - **They are not from real users**; no dictation log exists yet. They show which *kinds* of
    input break each approach, not how often those kinds occur.
- **Models:** `gpt-6-luna` (effort `none` and `low`), `gpt-5.4-nano` (`none`), `gpt-5-nano`
  (`minimal`, today's default for `text_parse`) and `gpt-4o-mini` (temperature 0).
- **Request:** Chat Completions with a strict JSON schema: `name`, `quantity`, `unit` and
  `food` for each item. One system prompt covers every language and contains **no word
  lists**, so a new language needs nothing added.
- **Scoring:** a list counts only if every item is right, in order, with case and punctuation
  ignored. The unit may be split off the name: "2 bottles of organic milk" can come back as
  2 + bottles + "organic milk". The `food` flag is scored on the hard sentences.
- **Reproduce:** `script/dictation_eval/run.sh` (README beside it). It uses a throwaway test
  database, never the development one. The tables are in `script/dictation_eval/results/`.
  The five models together cost about $0.07.
- **Prices** are OpenAI's Standard tier, per 1M tokens input / output ✅
  ([pricing](https://developers.openai.com/api/docs/pricing), read 2026-11-18):
  `gpt-6-luna` $0.10 / $0.50, `gpt-5.4-nano` $0.20 / $1.25, `gpt-5-nano` $0.05 / $0.40,
  `gpt-4o-mini` $0.15 / $0.60.

### Results 🧪

"Lists" is the share of lists exactly right. "Items" is the share of expected items that
appear at all. Costs use the measured average tokens per call.

| | Hard (20) lists | Hard items | All 152 lists | Tokens in / out | **USD per dictation** | Median / 90th pct. latency |
|---|---|---|---|---|---|---|
| `Text::Segmenter` | 15 % (3) | 63 % | 89 % | – | **$0** | ≈ 0 |
| `gpt-6-luna` none | **90 % (18)** | 94 % | 82 % | 301 / 67 | **$0.000064** | 1.5 s / 2.3 s |
| `gpt-6-luna` low | 90 % (18) | 94 % | 84 % | 301 / 168 | $0.000114 | 2.1 s / 3.8 s |
| `gpt-4o-mini` | 90 % (18) | 94 % | 82 % | 302 / 61 | $0.000082 | 1.5 s / 2.2 s |
| `gpt-5.4-nano` none | 85 % (17) | 93 % | 79 % | 301 / 67 | $0.000144 | 1.1 s / 1.4 s |
| `gpt-5-nano` minimal | 75 % (15) | 81 % | 74 % | 301 / 73 | $0.000044 | 1.3 s / 2.0 s |

- **Margin of error.** With 20 hard cases, 18 right has a 95 % Wilson interval of about
  70–97 %, and 3 right about 5–36 %. The gap is real; the order among the top three models is
  not established.
- **Reasoning effort `low` bought nothing:** same accuracy, 2.5× the output tokens, and slower.
- **Food flag:** on every hard list whose items were right, every `food` flag was right too
  (17 of 17 for `gpt-6-luna`). Toilet paper, Spülmittel, Küchenrolle and Kerzen were all
  marked non-food.
- **No prompt caching applies.** The prompt is about 300 tokens, and OpenAI caches only from
  1,024 ✅ ([prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching)).

**Why the models score lower on the generated lists.** The seeded dictionary is built for
receipts: it holds abbreviations ("gurk sal stck") and transliterations ("kaese", "aepfel"). The
generator then puts two names for the same product side by side ("käse kaese"). The models
"fixed" these: they split the abbreviation, respelled "broetchen" as "Brötchen", and merged
duplicates. A recogniser never writes "kaese", so those lists are not speech. On the subset a
person could say (spoken spellings only, no product twice; 28 EN and 34 DE lists, scored by
`rescore.rb`), `gpt-6-luna` none got **89 % / 91 %** and the segmenter 100 %.

**What the models still get wrong.** All of these are plausible readings without commas:
- Adjacent nouns are merged: "rice toast", "spinach quark", "Yuzu Tahini".
- A phrase is rewritten: "Tomaten aus der Dose" came back as "Dose Tomaten".
- An item after "wir haben keinen" ("we have no") is sometimes dropped: "wir haben keinen
  spaetzle dann salmon" gave only salmon.
- "something for Sunday" is dropped as not an item.

**What the segmenter gets wrong** is the opposite: it is literal. Every hard failure keeps the
spoken words, in the wrong lines:
- `ähm · Milch · nee warte Hafermilch`
- `peanut · butter`
- `chicken · breast · chicken · thighs`
- `bread · at the bakery · milk`

### Segmenter first, model only when it is unsure 🧪

The gate is a fact the segmenter already has, not a new rule: whether **every line was
accounted for by the lexicon**, i.e. an optional amount, unit or modifier, then a known item
(`confident.rb`).

| Hybrid with | Fixture | Hard | Generated EN | Generated DE | **All** |
|---|---|---|---|---|---|
| `gpt-6-luna` none | 11/12 | 18/20 | 60/60 | 60/60 | **149/152 (98 %)** |
| `gpt-4o-mini` | 11/12 | 18/20 | 60/60 | 60/60 | 149/152 |
| `gpt-5.4-nano` none | 11/12 | 17/20 | 60/60 | 60/60 | 148/152 |
| `gpt-5-nano` minimal | 11/12 | 15/20 | 60/60 | 60/60 | 146/152 |

- **The gate was never wrong when sure:** 0 of 130 confident answers were wrong. It sent 22
  cases to the model: 19 of the 20 hard ones, and 3 fixtures.
- **What the hybrid costs is unknown.** It is at most $0.000064 a dictation. It depends on how
  often real speech contains a word the kitchen's lexicon lacks. This set's 22 of 152 says
  nothing about that, because the hard cases were written to be unknown.
- **The rate falls as kitchens are used.** Every correction and typed line grows that kitchen's
  lexicon (§15.9), so fewer dictations need the model.
- **Measure it, don't guess it:** log `escalated=true|false` beside the gesture fields
  (§15.8.5).

### What it would take, and the risks

- **Latency is the real cost.** The lines would appear 1–2 s after release instead of at once.
  4 of 760 calls (`gpt-5.4-nano` 3, `gpt-4o-mini` 1) got no answer within 60 s.
  - A hybrid therefore needs a **short timeout with the segmenter's lines as the fallback**,
    so the mic never waits on OpenAI.
  - The right timeout is a heuristic to measure, not a figure from this run. Latency here was
    measured from this Mac, not from the Fly region.
- **Single run, model drift.** Reasoning models take no temperature, and answers can change
  between runs and model versions. Rerun `run.sh` when a model changes.
- **Transcripts would leave our server.** Today a browser transcript stops at our API. With
  a hybrid, the unsure ones go to OpenAI, which already receives recordings and receipt photos.
  They also count toward the daily AI budget (`Ai::Budget`).
- **Dropping non-food is a product decision, not a model one.** The model flags it reliably. But
  the memo is a shopping list, and toilet paper belongs on it. The flag fits capture (what goes
  into the fridge) better than the memo.

**Found on the way: deprecations that affect the app now** ✅
([deprecations](https://developers.openai.com/api/docs/deprecations), read 2026-11-18):
- **`gpt-5-nano` and `gpt-5-mini` shut down on 11 Dec 2026.** They are `Ai::Config`'s
  OpenAI defaults for receipts, text and recipes. OpenAI names `gpt-6-luna` and
  `gpt-6.1-terra` as replacements.
- **`gpt-4o-mini-2024-07-18` shuts down on 14 Jan 2027.**
- **`gpt-4o-mini-transcribe` shuts down on 26 Feb 2027.** The replacements are
  `gpt-transcribe` and `gpt-live-transcribe`, and their prices were not checked here.

`gpt-6-luna` is "Our most efficient model for focused, high-volume tasks". It supports
Chat Completions, structured outputs and reasoning effort `none` ✅
([model page](https://developers.openai.com/api/docs/models/gpt-6-luna)).

### 15.11.1 What was built: `Memo::ListReader` (2026-11-18)

Built so the hybrid can be evaluated. Nobody is asked to fix, confirm or correct anything at any
step.

**Who does what, and when.** Every step runs on our server (the Rails API), on each
`POST /memo/dictate`. That covers the browser's transcript and the recorded-audio path, after
transcription.

| Step | Who | When | What happens |
|---|---|---|---|
| 1 | Server: `Text::Segmenter` | Every dictation | Splits with the kitchen's lexicon. Free. Reports `sure`: every line is a known item, optionally after an amount, unit or modifier. |
| 2a | Server | `sure` | Its lines are saved. No model call. Logged as `path=segmenter reason=sure`. |
| 2b | Server | Not sure, AI off (stub mode or no key) | The segmenter's lines are saved as said. `reason=ai_off`. |
| 3 | Server: `Ai::Router`, `memo_parse` on `gpt-6-luna` with effort `none` | Not sure and AI live | The sentence is sent with `Memo::ListPrompt`, the measured prompt byte for byte, with one deadline for the whole provider chain. |
| 4a | Server | The model answered, and every name is made of words that were said | The model's lines are saved, as "2 Kilo Kartoffeln". `path=model`. |
| 4b | Server | The model was too slow, down, over the daily budget, returned something unusable, or named a word nobody said | The segmenter's lines are saved as said. `path=fallback`, `reason=timeout`, `unavailable`, `budget`, `invalid` or `ungrounded`. Nothing said is lost. |

**What is decided by data, and what is a heuristic**
- **The gate is not a threshold.** It is the segmenter's own record of whether any word was
  left over.
  - Its spec asserts that `sure` never covers a line the lexicon does not know, over 300
    random sentences.
  - Every generated dictionary list must come back `sure`, so no model call is wasted on them.
- **The grounding check is an invariant: the model may only choose among the words said.**
  - In the measured run it would have rejected only two answers, both respellings of receipt
    transliterations ("broetchen" → "Brötchen") that a recogniser does not produce.
  - It would also reject a respelled spoken word. `reason=ungrounded` counts how often.
- **`TIMEOUT` = 4 s is a heuristic.** `AI_MEMO_PARSE_TIMEOUT_SECONDS` overrides it.
  - It rests on one run from a laptop: all 152 `gpt-6-luna` answers came within 3.2 s.
  - It fails whenever production is slower. Every dictation logs `model_ms`, so it is tuned
    from Fly, not from this run.

**How to evaluate it.** `script/dictation_eval/run.sh live` sends all 152 cases through the
real `Memo::ListReader`, with OpenAI only. It prints the rows right per set, the path
counts, the model wait and the cost from the `AiCall` ledger. With AI off it reproduces the
gate: 130 of 152 `sure`, as in the simulation above.

**Measured end to end, 2026-11-18 🧪** (`results/2026-11-18-hybrid-live.txt`; one run, from a
laptop):

| | Right | Model called |
|---|---|---|
| Fixtures | 11/12 | 3 |
| Hard sentences | 18/20 | 19 |
| Generated EN / DE | 60/60 / 60/60 | 0 / 0 |
| **All** | **149/152 (98 %)** | **22** |

- **Path.** 130 dictations went to the segmenter (sure) and 22 to the model. None fell back:
  no timeout, no error and no ungrounded answer.
- **Wait for a model answer.** Median 1.5 s, 90th percentile 1.8 s, slowest 2.7 s. All are
  inside the 4 s deadline.
- **Cost.** $0.000057 per model call by the `AiCall` ledger, $0.0013 for all 22.
- **The production code matches the simulation exactly.** It got 149 of 152 right, with
  the same three cases wrong:
  - "something for Sunday" was dropped as not an item;
  - "Yuzu Tahini" was kept as one line;
  - "Tomaten aus der Dose" came back as "Dose Tomaten".
- **These numbers do not give production's model-call rate or wait.** The hard sentences
  were written to contain unknown words, and the wait was measured from a laptop. Production
  logs (`path`, `model_ms`) answer both.

**The three misses, analysed and acted on (2026-11-18).** None was the model malfunctioning.
Each case was compared across all five models:

| Said | Cause | Action |
|---|---|---|
| "milk toilet paper and something for Sunday" | All five models dropped the reminder, because the prompt says to leave out when and why. The fixture expected the reminder kept: two of our own rules conflicted. | **Product decision: a vague reminder is not a line.** The fixture now expects `milk · toilet paper`. The segmenter alone still keeps every unknown word, so nothing is lost without a model. Its fixture spec is now *right, or not sure*: it may never be confidently wrong. |
| "Yuzu Tahini und Gochujang" | Ambiguous without a pause. The segmenter and 3 of 5 models read "Yuzu Tahini" as one product, and neither word is in the dictionary. Whether such a product exists was not checked. | None in code. The lever is dictionary data, grown by the team at seed time. |
| "Rinderhack Tomaten aus der Dose und Basilikum" | The model read it correctly: name "Tomaten", unit "Dose". Our line format, amount + unit + name, then wrote "Dose Tomaten". | **Lines keep the speaker's words.** The line is the shortest stretch of the transcript holding the item's name and unit words, used only when the words in between belong to no other item and, given an amount, are not a number. Otherwise it falls back to amount + unit + name, and the amount is always digits. |

Replaying the saved `gpt-6-luna` answers through the changed code, with no new calls, gives
**151 of 152**. The one left is "Yuzu Tahini".

**Second live run, after these changes** 🧪 (`results/2026-11-18-hybrid-live-2.txt`):
**150 of 152**. Fixtures 12/12, hard sentences 18/20, generated lists 120/120.
- **Both fixes held:** the reminder is gone, and "Tomaten aus der Dose" is kept as spoken.
- **One timeout.** "zwei Kilo Kartoffeln drei Zwiebeln und eine Packung Spaghetti" got no
  answer within 4 s.
  - The reader fell back to the segmenter's lines (`2 Kilo · Kartoffeln · 3 Zwiebeln ·
    Packung Spaghetti`), so nothing was lost, just less tidy.
  - Our ledger records the call as failed and unbilled. Whether OpenAI bills a request we
    abandoned was not checked.
- **Model waits over this run's 22 calls:** median 1.6 s, 90th percentile 2.1 s, then 3.4 s
  and the timed-out call. The first run's slowest was 2.7 s.
- **Two runs (44 calls) are too few to set the deadline.** One call in 44 timed out, from a
  laptop. Raising the deadline trades a longer wait for fewer untidy fallbacks. That should
  be decided from production's `model_ms` and `reason=timeout` counts, not from this.

**Known limits, not handled**
- **The model can come back short.** Across 152 cases `gpt-6-luna` returned 15 items fewer
  than expected, mostly merged neighbours and removed duplicates, plus a few real drops
  ("wir haben keinen spaetzle dann salmon" gave only salmon). No check can tell a dropped
  item from a self-correction, which is meant to drop words. Production logs `lines` per
  dictation, but not what was expected, so this is measured only by the eval.
- **The fallback providers are unmeasured.** If Gemini or Groq keys are set, they take over
  within the same deadline when OpenAI fails. Their quality on this task was never measured.
- **Request logs contain what people say.** Rails' default request log, at the `info` level
  in production, prints every request's parameters. That includes `transcript` and every
  typed memo line, because `config.filter_parameters` does not filter them. The new dictation
  log line itself carries no text. Filtering them is a privacy decision of its own.
- **The correction learning is still in the code.** The rename chip and
  `Memo::LearnFromCorrection` (§15.9) depend on users fixing lines, which the product does
  not want. They have not been removed yet.

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
  [OpenAI `gpt-6-luna`](https://developers.openai.com/api/docs/models/gpt-6-luna) ·
  [OpenAI `gpt-5.4-nano`](https://developers.openai.com/api/docs/models/gpt-5.4-nano) ·
  [OpenAI `gpt-5-nano`](https://developers.openai.com/api/docs/models/gpt-5-nano) ·
  [OpenAI deprecations](https://developers.openai.com/api/docs/deprecations) ·
  [OpenAI prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching) ·
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
