# 13. The MVP Build — what exists, what does not, and why

*Docs 0–12 are research. This one describes the software that now exists in this repository,
which of their conclusions it implements, and — the more useful half — which it does not.*

> ⚠️ **Doc 0 says "no code should be written until the Berlin concierge test reports."** This
> build does not overturn that. It is a working prototype of the loop, useful for putting a
> real thing in front of the 25 households rather than a mockup, and for pricing the model
> calls against a real invoice. **It is not a launch, and the kill criterion in doc 6 still
> governs.**

---

## 13.1 Scope

Five features were specified. All five are built.

| # | Feature | Where |
|---|---|---|
| 1 | Anonymous fridge identity — cookie + localStorage | [`fridge_identifiable.rb`](../app/controllers/concerns/fridge_identifiable.rb), [`fridge.service.ts`](../frontend/src/app/core/services/fridge.service.ts) |
| 2 | Capture: camera with auto-shutter, voice, minimal manual | [`captures_controller.rb`](../app/controllers/api/v1/captures_controller.rb), [`capture.ts`](../frontend/src/app/features/capture/capture.ts) |
| 3 | Shopping memo with autosuggest from history | [`suggester.rb`](../app/services/memo/suggester.rb), [`memo.ts`](../frontend/src/app/features/memo/memo.ts) |
| 4 | Vision + speech via the OpenAI API, with a cost ledger | [`ai/`](../app/services/ai), [doc 14](14-mvp-cost-model.md) |
| 5 | Installable PWA | [`manifest.webmanifest`](../frontend/public/manifest.webmanifest), [`sw.js`](../frontend/public/sw.js), [`install.service.ts`](../frontend/src/app/core/services/install.service.ts) |

---

## 13.2 The four decisions worth defending

### Identity is a token in two places, and that is the whole account system

Doc 2 §2.9 rule 8 — *value before permission, permission before account*. So there is one
optional question and a Skip. The token lives in localStorage **and** in a signed ten-year
cookie, re-stamped on every request; either one alone restores the fridge, verified by
clearing localStorage entirely and reloading.

**The trade, stated plainly:** clear both, on every phone that has opened the kitchen,
and the fridge is gone. For a product whose entire inventory is rebuilt by one photo of
the next shop, that is a better deal than a sign-up form.

### A second phone joins with a code, not with the token

`token` is the bearer secret, so the share link does not carry it. Each fridge also has
a `join_code`. Settings shows a link and a QR code for `/join#<code>` — the code is in
the fragment, so loading the page does not send it to the server. The page posts it to
`POST /api/v1/fridge/join`, which sets the same ten-year cookie and returns the token
for localStorage. The join code is not accepted as a bearer. Revoking a share is not
built. The shopping memo was already per fridge, so a joined phone sees the same list;
the screen says so, and there is no second list. A name typed on the phone lives in
localStorage only and is stored on the capture, its items, and memo lines as
`added_by_name`. There is still no account and no user row.

### Spoilage never fires an alert on its own

This is doc 0's correction #1, and it is the reason the app is not just an inventory list:

```
risk = P(still present) × P(gone off)
```

`P(still present)` is a half-life curve on the household's own repurchase cadence, read out
of capture history — free, and the personalisation doc 5 §5.4c defers. Observed live: chicken
bought seven days ago scores `spoilage = 1.0` and is **not** alerted, because
`presence = 0.088`. Without that multiplication it would be the loudest thing in the app, and
it has almost certainly been eaten.

⚠️ **One acceptance criterion was recalibrated rather than met.** Doc 3 R4b AC1 sets the alert
floor at `P(still present) ≥ 0.6`. Against this curve that floor is unreachable — presence
falls below 0.6 before spoilage rises at all, for every category in the seed table, so a 0.6
floor means the app never alerts about anything. The floor is set to **0.30**, which is where
this curve sits at doc 3 §3.4's own worked example: broccoli on day 8. The *intent* of AC1 is
kept; the constant is calibrated to the curve underneath it. **This should be re-derived from
the Phase 0 diary study rather than trusted** — it is the single most load-bearing number in
the build. Reasoning is in [`presence_model.rb`](../app/services/freshness/presence_model.rb).

Against doc 3 §3.4's canonical broccoli timeline:

| Day | Doc 3 says | This build does |
|---|---|---|
| 0 | "fresh · ~10 days" | "fine for about 10 more days" |
| 5 | aging, silent | aging, `alertable = false` |
| 8 | at risk, "use in the next 2 days" | at risk, `alertable = true` |
| 11 | ghost candidate | at risk, still shown, no alert |
| 13 | auto-retired | auto-retired day 12 |

### The camera decides when to shoot

Doc 2's post-shop budget is 30 seconds for a whole shop, and tap-to-shoot spends a
surprising amount of that on framing, missing and retaking. The client samples frames at 8fps
and measures motion, edge density and brightness; steady + detailed for ~0.75s fires the
shutter. Manual shutter always available, because an auto-shutter that will not fire is worse
than none.

**Deliberately not object detection.** Shipping a model to the client to tell a receipt from a
worktop would cost megabytes and battery to answer a question the extraction call answers
anyway. The client only decides whether a request is worth making; the server's single call
classifies *and* extracts, so the user never picks "receipt" or "food" from a menu.

### The bill is a product surface

Every model call writes an `AiCall` row including failures, and `/settings` shows the running
total and cost per receipt. The claim "a capture costs a fraction of a cent" is load-bearing
for the whole business case, so it is made falsifiable by the people paying for it. Full
analysis in [doc 14](14-mvp-cost-model.md).

---

## 13.3 What is deliberately absent

| Not built | Why |
|---|---|
| **Rescue ideas** ("what can I cook with this") | Out of the five-feature scope. It is the top of §13.4 — without it the Used/Wasted buttons have no reason to be pressed. |
| **Email fallback for notifications** | Doc 5 §5.7 wants one for the ~25–30% of German users who will never get push (iPhone without Home Screen install, or a no). Kitchens have no email address, so there is nowhere to send it. Web Push is built — see §13.4b, *notifications*. |
| **An adaptive notification budget** | Doc 5 §5.5 lowers a kitchen's budget after two ignored notifications. `notifications.opened_at` records the taps; nothing reads it yet. Send time is the fixed 17:00–20:00 window, not learned. |
| **Email/digital receipt import** | Doc 2 §2.4b promotes it to v1 P0 as the only capture path immune to forgetting. Significant work — retailer accounts, an ingest address, parsing. |
| **The two German checksums** | Doc 12 §12.1's `Summe` reconciliation and VAT-class subtotals are the confidence score that replaces the vendor's. `RECEIPT_LINE.vat_class` is captured in the prompt but not reconciled, so `parse_confidence` is currently just the share of lines that resolved. **This is the largest accuracy gap.** |
| **The second-pass tier** | ~15% of receipts should escalate to a stronger model. Not implemented: cheaper than doc 12's design and less accurate. |
| **The 60-second sweep** | `sweep_count` is computed and returned; no screen consumes it. |
| **Printed-date reading** | The estimator handles `Verbrauchsdatum` vs `MHD` correctly and clamps safety dates, but nothing populates `date_label_value` — no screen sets it and the prompt does not ask for it. **The safety carve-out is therefore code without an input.** |
| **`rule_id`/`rule_version` snapshots** | Doc 5 calls this the biggest migration hazard: recategorising a product silently re-dates live food in every household. Not modelled. |

---

## 13.4 What to build next, in order

1. **Rescue ideas.** One nano-tier call over the at-risk items. Cheap (~$0.00006), and it is
   what converts a list into a reason to open the app. Should have been feature six.
2. **The Summe checksum.** Turns `parse_confidence` from a guess into a measurement, and it is
   free — the number is already printed on every German receipt.
3. **The email fallback and the adaptive budget.** Web Push and the weekly ledger exist
   (§13.4b); the ~25–30% who will never get push still have to remember to open the app.
4. **Printed-date capture**, so the safety carve-out has an input.
5. **The 200-receipt corpus**, then decide `gpt-5-mini` vs `gpt-4o-mini` on measured
   line-level F1 — see [doc 14 §14.5](14-mvp-cost-model.md#145-model-choice--measured-against-the-bill).

---

## 13.4b What a live API key found

Wiring a real `OPENAI_API_KEY` in surfaced four defects that the stub could not, all now
fixed. Worth recording because three of them are the *same* mistake — a failure path that
was never exercised.

| Found | Fix |
|---|---|
| **`.env` was never loaded.** `docker compose` reads it for substitution, but a native `bin/rails server` does not — so the documented setup silently ran against the stub while appearing configured. | `dotenv-rails` in dev/test. |
| **The test suite stopped being hermetic.** With dotenv loading `.env` in test too, `rspec` inherited a real key with `AI_MODE=auto` *and* `DATABASE_PATH` pointing at the **development** database. Unguarded it would bill every capture example and truncate real data. | Forced in `spec/rails_helper.rb` before boot. Caught by `ActiveRecord::EnvironmentMismatchError` before any write; no data lost. |
| **"That one was hard to read" on a quota error.** The provider returned 429 for every call, and the app told the user to retake a photo that could never succeed — a loop with no exit. | `Ai::Client::Unavailable` split from `Error`; quota/auth/outage now says photo reading is off and points at the paths that still work. |
| **One unknown word destroyed the whole capture.** `milch, brokkoli, yuzu kosho` returned *nothing*: two free dictionary hits were discarded because the third word needed a model that was refusing. Straight violation of doc 4 §4.4 rule 4. | Dictionary hits are kept and the unparsed remainder is reported. Voice now routes through the dictionary too, so a spoken sentence of familiar words costs nothing. |

### And what a *funded* key found

Reading one real receipt exposed three more, all fixed:

| Found | Fix |
|---|---|
| **Reasoning tokens returned an empty answer for $0.0005.** gpt-5 spends `max_completion_tokens` on thinking before it writes; a 1,200-token budget went entirely on reasoning. | `reasoning_effort: "minimal"` on the gpt-5 family. 7.6× cheaper, 5× faster, and it works. |
| **Bread was filed as dairy and given a 14-day fridge window.** The dairy keyword `"ei"` is a substring of `"weizenbrötchen"`. Exactly the false-expiry failure doc 3 §3.4 attributes to Fridgely. | Keywords under four characters must now match a whole word; longer ones still match inside German compounds. |
| **A truncated line got a 180-day window.** The till printed `RISPENTOMAT.`; the dictionary held `rispentomaten`, and the candidate guard rejected the prefix match it had already found. So a tomato was filed as "other" and sent to the pantry. | Prefix-aware overlap scoring in `ProductAlias.token_match`. |

Two smaller additions came out of the same session: a **file-picker fallback** for photos —
without it there is no photo path at all on a desktop or with camera permission refused —
and **failed-call count on the cost screen**, which otherwise read "7 calls · $0.0000" and
looked like the AI was free when in fact every call was being refused.

### And what a code review found

A read of the whole codebase against docs 0–12, then each finding driven in a local
browser, found five defects worth fixing first, and two more surfaced while testing
the fixes. All seven are fixed and covered by specs.

| Found | Fix |
|---|---|
| **One anonymous fridge could rename a word for every kitchen.** `ProductAlias` was global and a rename overwrote the shared row, seeded ones included. Doc 7 B6 names this exact risk. | Corrections carry a `household_id` and are read before the shared dictionary only in that kitchen. The shared layer is written by seeds. **Promotion at k≥5 households (doc 5 §5.6) is still not built.** |
| **A failed boot request could lose the kitchen.** Offline, a 5xx or a waking machine wiped the token; the phone landed on the welcome screen, and Skip minted a new fridge over the cookie. | The client forgets the token only on a 401. `POST /fridge` returns the fridge a browser already holds instead of minting another. |
| **A correction fixed the label and kept the harm.** Bread filed as dairy, renamed in the Kitchen, kept dairy's 14-day window, and the dictionary learned the new name with the old category. | `Items::Correct`: a rename re-reads the category, a changed category, storage or printed date re-dates the item, and the dictionary learns the corrected pair. |
| **No way to remove a misread line.** Doc 4 §4.4 makes subtracting the user's one job on the review sheet, and there was no delete anywhere in the UI. | A 48px remove button per review line, calling the household-scoped `DELETE /items/:id`. |
| **A truncated model answer was a 500.** `JSON::ParserError` is not an `Ai::Client::Error`, so it escaped every handler and lost the dictionary hits. An empty answer also wrote two ledger rows. | Unparseable content is an `Error` ("hard to read"); a non-JSON body is `Unavailable`; one ledger row per call, carrying its cost. |
| **Groq's defaults named Gemini's models**, so every Groq call 404'd and fell through. | Groq uses `llama-4-scout` (price ⚠️ unverified). Models carry their provider, and a spec holds each provider to its own. |
| **A connect timeout skipped the fallback.** On Ruby 3.4 it is `IO::TimeoutError`, which the client did not rescue. Found while testing the above. | Every transport failure family is `Unavailable`. |

### And what a browser QA pass found

Every screen was driven at phone width, in both themes, with the model stubbed.
24 issues were found and fixed, then a second pass re-tested all of them and
found four more, also fixed. The ones that change how the app behaves:

| Area | Now |
|---|---|
| **Layout** | The page ends above the fixed tab bar and add button. Before, a phone could not reach Today's "Fine for now", the Kitchen's lower groups, or "Forget this fridge". |
| **Undo** | Every one-tap outcome (used, gone, half, froze, opened, moved) shows a toast with Undo that stays until closed (WCAG 2.2.1); `POST /items/:id/undo` restores the item for ten minutes. The lists reorder after each tap, so a mis-tap used to be permanent. |
| **Opened** | Failed with 422 on any food opened before its window began, which is most food. |
| **Language** | The client never sent `X-Locale`, so every sentence the server wrote was English. It does now; Settings has a language switch. The tap grid shows the UI language but sends the receipt's word, so a tap and a Bon land on one Kitchen line. |
| **Shop** | No suggestion for food still at home; suggestions can be dismissed (`suggestion_dismissals`); one open line per name; "Clear bought". |
| **Join** | `POST /fridge/preview` names the kitchen before switching; the phone remembers the kitchen it left and Settings offers the way back. The create and join rate limiters no longer share one counter. |
| **`/costs`** | Reports only the asking kitchen. The global ledger, provider chain and model table were readable by any free fridge. |
| **Input** | Item names ≤120 characters, known categories, quantity ≥0; a typed or spoken capture ≤1,000 characters. Validation answers in one translated sentence, not column names. |
| **Safety badge** | "Go by the date" only when a Verbrauchsdatum was read; a risky category alone is high risk without claiming one. |

One regression was caught only in the browser, which is why `app.config.spec.ts` exists: an
interceptor that injected `TranslateService` ran on the translation loader's own request and
booted the app to a blank screen (NG0200). Interceptors now act on API calls only.

### And what moving food between places needed

The Kitchen showed one place at a time; opening the Freezer closed the Fridge and pushed the
Cupboard out of reach. Only fridge → freezer existed ("Froze it"). Now, following NN/g on
accordions and drag-and-drop, WCAG 2.5.7, and the touch studies summarised in the research
pass (tap beats drag; hidden gestures go unfound):

- **All three places on one page**, with a row under the app bar that stays in view and jumps
  to each, with its count. The app bar never actually stuck (`<app-root>` was inline); it does
  now, at a fixed `--appbar-h`.
- **"Fridge ▾" on each card** opens a sheet of the three places, current one marked. It
  replaces "Froze it" in the Kitchen; Today keeps the one-tap freeze.
- **`outcome: "moved", to:`** on `POST /items/:id/resolve`, so a move is undoable like every
  other tap. Into the freezer is recorded as freezing. Out of it is a thaw: two days for
  meat and fish (USDA FSIS, "The Big Thaw"), three for anything else ⚠️ *our estimate*.
  Otherwise **a move never lengthens the window**: milk put in the cupboard would have
  inherited the cupboard's generic six months, because no dairy-in-cupboard rule exists.

### And what notifications needed

Doc 4 §4.9 calls the evening notification *the product*. It is Web Push (`web-push` gem,
VAPID keys as Fly secrets), at most 1 a week by default and 3 at most, and only when
something is alertable — `RiskScorer#alertable?`, so presence is multiplied in and a
notification is never spent on food that is probably eaten.

- **The clock is outside the app.** The machine sleeps (`min_machines_running = 0`), and a
  scheduler inside a stopped machine never fires, so Solid Queue's `recurring.yml` is not
  used. An hourly Fly machine POSTs `/internal/notifications/tick`, which wakes this one.
  The tick takes no input, needs a bearer token of at least 32 characters (compared in
  constant time, fails closed when unset), and answers anything else with 404.
- **The ledger is the lock.** `notifications` has unique indexes on (kitchen, ISO week, slot)
  and (kitchen, day). The row is written before anything is sent, so a repeated, late or
  concurrent tick sends nothing twice. The send window is 17:00–20:00 in the kitchen's time
  zone, so one missed tick still delivers.
- **Delivery is one job per phone, on Solid Queue.** It runs inside Puma in `async` mode (one
  process on a 512 MB machine), with its own SQLite file beside the primary. Push-service
  outages retry with backoff and survive the machine stopping (`kill_timeout = 60`,
  `shutdown_timeout` 50 s); 404/410 forgets the phone; a refused VAPID key fails loudly
  instead of deleting every subscription. The message is built at delivery, so food used up
  in between is left out, and high-risk food only ever gets "worth a look".
- **Push endpoints are allowlisted** (FCM, Mozilla, Apple, WNS, https, port 443): the server
  POSTs to whatever is stored, so anything else would be an SSRF hole.
- **Permission is asked on the first capture review**, not at onboarding (doc 2 §2.7: value
  before permission), and inside the tap, because Safari refuses a prompt that is not.
  Settings has the switch and the budget. iPhone Safari gets the Home Screen instruction,
  since push exists there only for an installed app.

⚠️ **Not verified on a real phone.** The specs stub the push service; delivery through FCM or
APNs, the lock-screen tap, and Fly's scheduled machine have not been exercised end to end.

---

## 13.4c Deployment

Live at **https://scrapless-app.fly.dev** — one 512MB shared-CPU machine in `fra`, a 1GB
volume for SQLite, `auto_stop_machines` on so it sleeps when idle. Rails serves the built
Angular app from `public/`, so production is single-origin and CORS is never exercised.

Secrets (`RAILS_MASTER_KEY`, `SECRET_KEY_BASE`, `OPENAI_API_KEY`, `AI_MODE`,
`AI_DAILY_BUDGET_USD`) are Fly secrets, piped to `fly secrets import` on stdin so no value
reaches an argument list or a log.

**Notifications need three more secrets and the clock, once.** Without the keys the feature
is simply off: the client is told there is no key and offers nothing.

```sh
# VAPID keys and the tick token, generated locally and piped in, never typed as arguments
bin/rails runner 'k = WebPush.generate_key; puts "VAPID_PUBLIC_KEY=#{k.public_key}", "VAPID_PRIVATE_KEY=#{k.private_key}"; puts "NOTIFY_TICK_TOKEN=#{SecureRandom.hex(32)}"' \
  | fly secrets import

# The clock: an hourly machine in the same app, which receives the same secrets as env.
# It only rings the bell; the app decides who is due.
fly machine run curlimages/curl --schedule hourly --restart no --region fra \
  --entrypoint /bin/sh -- -c \
  'curl -fsS -X POST -H "Authorization: Bearer $NOTIFY_TICK_TOKEN" https://scrapless-app.fly.dev/internal/notifications/tick'
```

⚠️ **Not run yet — check each of these on the first setup:** the flags against
`fly machine run --help`; that a machine made this way receives the app's secrets (if
`$NOTIFY_TICK_TOKEN` is empty there, every tick gets a 404 — it fails closed, and `fly logs`
shows it); and, after the next `fly deploy`, that the scheduled machine is still there on the
curl image (it is not in a process group, so deploys should leave it alone).
Rotating the VAPID keys invalidates every subscription: phones re-subscribe on their next
visit when they tap "Turn on" again.

⚠️ **Two things had to be fixed before it was safe to expose.**

1. **`.dockerignore` did not exclude `.env` or `config/master.key`**, so `COPY . .` would
   have baked the OpenAI key, the Fly deploy token and the Rails master key into an image
   layer. Now excluded, and verified by building a throwaway image that asserts their
   absence from the build context. *(This comes from the scaffold generator's overlay and is
   worth reporting upstream — every project generated from it has the same hole.)*
2. **The wallet was open.** `POST /api/v1/fridge` is unauthenticated and fridges are free, so
   the per-fridge capture limit was no defence at all — doc 5 §5.6's "anyone could use
   Scrapless as a free receipt-OCR API", exactly. Now bounded by
   [`Ai::Budget`](../app/services/ai/budget.rb), a daily spend ceiling counted out of the
   `ai_calls` ledger (not a cache counter, which a restart would reset), plus a Rails-native
   rate limit on fridge creation.

**The ceiling is $2/day by default** (`AI_DAILY_BUDGET_USD`). At the measured $0.0025 a
receipt that is ~800 receipts a day; set it to `0` to disable. When it trips, the app degrades
exactly as a provider outage does — camera off, typing and voice still working.

Redeploy with:

```bash
fly deploy --remote-only -a scrapless-app
```

---

## 13.5 Verification

Backend 334 examples, frontend 61, RuboCop and Brakeman clean. Beyond the suites, the running app was
driven end to end: fridge created and named, four items added through the tap grid with
**zero** billed model calls, the shop rewound a week to exercise the risk model, chicken
correctly suppressed, localStorage cleared and the fridge restored from the cookie alone, and
a receipt image posted over real HTTP returning six items with `PFAND` suppressed and
`parse_confidence 0.86`.

**Verified against the live API, success path included.** A 12-line German Bon uploaded
through the real UI returned 11 food items with clean German names and sensible windows,
`PFAND` suppressed, for **$0.002453** — against a projected $0.0025. Measured numbers and two
surprises (reasoning tokens, and 15.7s latency) are in
[doc 14 §14.7](14-mvp-cost-model.md#147-observed--first-real-calls).

**A provider chain now backs it.** `openai → gemini` by default, with fallback on any
`Unavailable` (quota, credentials, outage, dead socket) and never on a bad answer. Every
attempt is recorded with its provider, so a silent failover cannot become a cost surprise.

**Not verified end to end: the camera auto-shutter against a live camera.** Its decision logic
has six unit tests and the frame analysis six more, but the browser available here would not
decode a synthetic video stream. **Test it on a real phone with a real Bon before trusting
it** — the thresholds in `DEFAULT_THRESHOLDS` are reasoned, not measured.
