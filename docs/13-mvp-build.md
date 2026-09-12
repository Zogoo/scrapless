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

**The trade, stated plainly:** clear both and the fridge is gone. For a product whose entire
inventory is rebuilt by one photo of the next shop, that is a better deal than a sign-up form.

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
| **Notifications** | Doc 4 §4.9 calls the Wednesday notification *the product*. It needs push infrastructure, an email fallback for the ~40% of iOS users who never grant push, and the 3/week ledger. The `NOTIFICATION` table is not in the schema. |
| **Email/digital receipt import** | Doc 2 §2.4b promotes it to v1 P0 as the only capture path immune to forgetting. Significant work — retailer accounts, an ingest address, parsing. |
| **The two German checksums** | Doc 12 §12.1's `Summe` reconciliation and VAT-class subtotals are the confidence score that replaces the vendor's. `RECEIPT_LINE.vat_class` is captured in the prompt but not reconciled, so `parse_confidence` is currently just the share of lines that resolved. **This is the largest accuracy gap.** |
| **The second-pass tier** | ~15% of receipts should escalate to a stronger model. Not implemented: cheaper than doc 12's design and less accurate. |
| **Household sharing** | Doc 3 R9, v1 P1. One token, one fridge, no members. |
| **The 60-second sweep** | `sweep_count` is computed and returned; no screen consumes it. |
| **Printed-date reading** | The estimator handles `Verbrauchsdatum` vs `MHD` correctly and clamps safety dates, but nothing populates `date_label_value` — no screen sets it and the prompt does not ask for it. **The safety carve-out is therefore code without an input.** |
| **`rule_id`/`rule_version` snapshots** | Doc 5 calls this the biggest migration hazard: recategorising a product silently re-dates live food in every household. Not modelled. |

---

## 13.4 What to build next, in order

1. **Rescue ideas.** One nano-tier call over the at-risk items. Cheap (~$0.00006), and it is
   what converts a list into a reason to open the app. Should have been feature six.
2. **The Summe checksum.** Turns `parse_confidence` from a guess into a measurement, and it is
   free — the number is already printed on every German receipt.
3. **The notification budget + email fallback.** Doc 4 §4.9. Until this exists, the product is
   something you have to remember to open, which doc 2 says nobody does.
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

---

## 13.5 Verification

Backend 125 examples, frontend 12, RuboCop and Brakeman clean. Beyond the suites, the running app was
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
