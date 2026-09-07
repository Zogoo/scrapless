# 7. Senior Staff Review — Findings & What Changed

> 📌 **Provenance note.** Both reviews were conducted against the **UK-first version** of this
> plan, before the launch market moved to Berlin/Germany ([doc 11](11-germany-berlin-market.md)).
> **Their figures are quoted in £ exactly as they were written** — editing a reviewer's numbers to
> match a later decision would misrepresent the review. Every finding is structural and survives
> the market change; where the German re-base *strengthens* an answer (the Belegausgabepflicht
> guarantees the receipt input; Berlin grants reduce the raise; PayPal/SEPA web checkout improves
> the margin) that is noted in Part C.

> ⚠️ **Read this in context.** Both reviews were conducted against the **UK-first** version of the
> plan, and their figures are in **£** as reviewed. The plan has since been re-based on a
> **Berlin → Germany → DACH** launch ([doc 11](11-germany-berlin-market.md)) and the receipt
> pipeline rebuilt around a vision LLM ([doc 12](12-technical-research-capture.md)).
> **Their findings are recorded verbatim rather than retro-fitted** — the reasoning stands, and
> Part C records where the German re-base changed the answer. Two of their criticisms were
> materially resolved by the later work: the cost model (VLM-first takes gross margin from 66% to
> ~95%) and the missing per-field confidence scores (German receipt checksums supply them).

Two independent senior reviewers read documents 0–6 cold and were instructed to be blunt
rather than agreeable. Their findings are recorded here **unsoftened**, followed by what was
changed in response and what was deliberately not changed.

---

## Part A — Senior Staff Product Engineer / former founder

**Verdict:** *"Would I join? No, not full-time at this scope. I would advise. Would I fund it?
Not as a venture bet at £750k–1M."* They would write a £150–250k pre-seed to fund a hard
4–6 week validation, asking a different question than Phase 0 currently asks.

The central charge: *"it is unusually well-written, and the quality of the prose is doing work
that the evidence isn't."*

### A1 — The thesis may invert cause and effect (severity: critical)
The plan says manual entry killed the category. The reviewer points at three refutations
sitting inside our own competitor table:

- **Cooklist** already has *lower* friction than us — loyalty sync, no per-shop obligation at
  all — and has not broken out. We dismissed this as "retailer-gated", which is *"a distribution
  excuse deployed to avoid asking whether zero-entry actually retains."*
- **Samsung** put a camera inside the fridge. User effort: zero. The loop still doesn't close.
- **Fango** *is* Crisper v1 — receipt-only, narrow, €2.99, 34 countries — and doc 1 cites it as
  **supporting** evidence with no revenue, user or retention data. *"The closest existing
  analogue to the proposed product is treated as encouragement rather than as the primary
  disconfirmation."*

Two further arguments we had entirely missed:
- **Selection inverts the value.** Waste correlates with large, chaotic, time-poor households
  with kids — the least likely to install and sustain the app. The people who install are
  already conscientious, so they waste least and get least value. *"Every app in the graveyard
  was used by the people who needed it least."*
- **Our own winner analysis condemns us.** We concluded Too Good To Go won on a *transaction*
  and an *immediate concrete reward*. v1 ships neither and defers the transaction to month 12+.

### A2 — We modelled the wrong error type (severity: critical)
The "inventory allowed to be wrong" doctrine only handles **false positives** (ghosts that
linger). It does nothing about **false negatives** — the shop you never photographed — and that
is the error that breaks the product, because you cannot warn someone about spinach you never
knew they bought. We never distinguished the two.

Their honest compliance forecast for "photograph the receipt after every shop": **~70–80% of
shops in week 1, ~40–50% by week 4, ~25–35% by week 8, ~20–30% by week 12.** Our 30-second
budget measures from *"tap add"*, excluding the real costs: keeping the receipt (UK shoppers
increasingly decline paper), finding it, flattening curled thermal paper, and above all
**remembering**. *"No UI fixes forgetting."*

Compounding the four independent conditions the Wednesday notification needs:
```
capture happened (~0.6) × item still present (~0.7)
  × shelf-life right ±2d (~0.7) × dinner not already decided (~0.6)
  ≈ 18% of notifications genuinely useful
```
We have no end-to-end alert-precision metric at all.

### A3 — Retention gates are undefined, measured on the wrong cohort, and testing the wrong build
- **Undefined:** "D30 ≥25%" never says what the qualifying event is. For an app deliberately
  invisible six days a week, open-based retention reads catastrophically low and means nothing.
  These numbers function as kill criteria and have no numerator or denominator.
- **Wrong cohort:** G2 requires W3 ≥35% on a *hand-recruited* 100-household beta — typically
  2–3× the eventual organic cohort — and is immediately followed by launch and paywall-on.
- **Backwards sequencing:** the three strongest retention mechanics in this category (household
  sharing, shopping list, what's-for-dinner) are all v2+. *"v1 ships the least retentive possible
  subset and then uses it to test retention. G2 is designed to fail."*
- **Arithmetic doesn't close:** D30 25% → W12 15% implies ~60% M1→M3 survival, best-in-class
  utility territory, while §6.7 assumes 6%/mo paid churn (top-decile). At a realistic 10%/mo,
  net of store fees and VAT (£2.99 gross ≈ £2.10–2.49 net), **LTV is ~£20–24, not £45.**
  And £8 "blended" CAC is really an *organic* CAC, which by definition doesn't scale — so the
  payback claim is circular.

### A4 — Restraint confuses "not interrupting" with "not being present" (severity: high)
Twelve interactions before an annual renewal decision, on a **variable** cue ("if nothing is at
risk, send nothing. Ever."). *"A variable, low-frequency, externally-generated cue is close to
the worst possible substrate for habit formation. The user doesn't get annoyed; the user
forgets the app exists. That is churn under a nicer name."*

Worse: the notification is the only surface, and it's the surface most likely not to exist.
iOS PWA install × push opt-in compounds to ~20–35%. **For roughly two-thirds of iOS users this
product has no surface whatsoever** — buried in a technical appendix rather than treated as
existential.

And the one artifact that would justify renewal — a periodic earned-value receipt — is P2, and
our own copy guide forbids anything that sounds like tracking. *"The doctrine has principled the
product out of the only thing that makes renewal legible."*

### A5 — The free/paid line is drawn backwards in both directions (severity: high)
- **The scan cap is inverted.** 4 scans/month ≈ one shop a week, so the modal household is
  *fully served free forever* and never hits the wall — while the 3×/week shopper (highest
  waste, highest value, most motivated) hits it in week two before any trust exists.
  *"It is a cost-accounting decision dressed as packaging."*
- **Everything retentive is paid.** Sharing, email import, don't-buy list, ideas and sweep are
  all Plus. So the free tier is the least retentive version of the product and free users churn
  before they can convert. **Free should contain the habit; paid should contain the leverage.**
- No consideration of a **lifetime/one-off price**, despite KitchenPal's $29.99 lifetime sitting
  unexamined in our own table — one-off pricing is what converts in low-salience utility categories.

### A6 — Missing screens, states and data (selected)
- **No onboarding screens exist in doc 4 at all**, despite doc 2 making them the most important
  screens in the app. Undesigned: the modal "on the sofa, no receipt to hand" install (6-day gap
  to first value), the 20-item tap grid, permission and install prompts.
- **Partial consumption is unrepresentable** — `ITEM` has no quantity or unit. You cannot express
  "2 of 4 chicken thighs" or "half the milk", and half-consumption determines the decay clock.
- **`opened` is a parameter with no input channel** — the ×0.35 multiplier exists, nothing sets it.
- **Freezer is in three states at once** (v3 in doc 3, a v1 action in §4.5, a section in §4.6,
  a ×8 multiplier in §5.4). And *"freezing is the most common real rescue behaviour, and
  unlabelled freezing is the top cause of freezer waste — there is a better product hiding here."*
- **Leftovers** — shortest fuse, highest guilt, highest frequency — deferred to v3.
- **The 3×/week shopper has no model**: no duplicate/merge detection ("is this another milk or
  the same milk?"), which bloats inventory and fires alerts on already-replaced items.
- **Last-write-wins is wrong for quantities** — two people decrementing produces a lost update.
- **No correction screen**, despite budgeting ≤2 taps for it and calling correction cost the
  dominant abandonment driver.
- **No holiday/away mode** — guaranteed to produce a fridge of false alerts on return.
- Also absent: paywall, account/household join, the alerts-budget screen the IA references,
  offline/sync-conflict states.
- **Contradiction:** "Probably gone 2 →" on Today is a visible cleanup to-do list, violating our
  own R7-AC2.
- **Accessibility:** Aging `#F9A825` (~1.9:1) and At-risk `#EF6C00` (~3.4:1) do not pass AA as
  text, though they pass as ≥3:1 non-text graphics. Our blanket "AA throughout" claim overstates.

### A7 — Intellectual honesty (severity: high — this is the diligence-killer)
- **The load-bearing citation for the core thesis** ("independent 2026 reviews converge") is
  three competitor content-marketing blogs, one of which (PantryPersona) is *in our own
  competitor table* — in a document that opens by dismissing market projections as "marketing,
  not evidence." The "~54% of days logged" figure is laundered through the same source instead
  of the primary study.
- **The trust-cliff chart is invented.** Seven precise points on an unlabelled axis, no source —
  and the 80–85% threshold it implies then propagates into the 85% F1 CI gate *as though derived*.
- **The item-mix pie chart is invented too**, and it justifies cutting barcode from v1. Also a
  denominator switch: 45% is "of items", but the claim used is "45% of *spoiling food*".
- **The ~30% RCT transfer is borrowed credibility.** That result came from structured
  intervention *plus human coaching* over months with observed participants. Turning it into
  "self-reported waste reduction ≥20% at day 60, RCT-anchored" uses one of the most biased
  instruments available.
- **Stopwatch fiction:** "⏱ 24 seconds total" annotated on software that does not exist, in a
  plan that insists the budget "is not aspirational copy".
- **LLM fallback rate has three different values** across the docs (15%, <5%, <20%, with a
  warning at 40%) — *"the entire gross-margin claim rests on this single unpinned variable."*
- **The unit cost model omits free-tier cost, store/payment fees, VAT and support.** At 3–5%
  conversion, free-tier cost per *paying* user is 20–30× the quoted figure. ">93% gross margin"
  is true only if you ignore every non-paying user.
- **Privacy contradiction:** an absolute "never sell your shopping data" promise in §5.6 versus a
  grocery basket hand-off in §6.3 that requires sharing basket contents with a retailer. Users
  will experience these as similar; the two are never reconciled.
- **Phase 0 burn** (£45k / 2 FTE / 6 wks ≈ £195k FTE-year) is inconsistent with every other
  phase (£121–127k) — *"the numbers weren't built from a model."*
- **§6.1 concedes** a £2–3M ARR realistic ceiling and then §6.6 raises £750k–1M against it.
  *"The honesty is stated but not acted on."*

### A8 — What they credited
Bottom-up TAM, the pre-written kill criterion, the `window_start`/`window_end` schema as
architecture enforcing a product promise, the refusal of streaks and shaming, the safety
carve-out for high-risk categories, and the receipt-privacy analysis — *"all better than
category standard."*

### A9 — The single change they would make
**Invert Phase 0.** It currently leads with "can we parse receipts to 85% F1" — *"the
engineering-shaped, fun, cheap-to-be-confident-about question, and honestly the one you already
know the answer to post-LLM. Bet 1 is not what kills you."*

Instead: a **six-week concierge**, ~£15k. 25 households, a WhatsApp group, humans parsing
photographed receipts by hand, humans sending the Wednesday message. **No code at all.**
Measure exactly two things:

1. **Week-over-week capture compliance** — what fraction of actual shops get photographed in
   week 1 vs week 6. *"This is the number the entire business rests on and there is currently
   no plan to measure it."*
2. **Rescue-on-prompt rate** — when a perfect, human-generated, perfectly-timed message arrives,
   what fraction of households actually cook the thing? **Software can only be worse than a
   human concierge**, so this is the ceiling.

Their prediction: *"compliance decays to the 30s and the rescue rate lands in the 20s, and the
useful finding will be that the households who stayed engaged did so because someone was telling
them what to cook, not what they owned."*

---

## Part B — Senior Staff Software Engineer

**Verdict:** *"The product thesis is sound. The plan as scoped and estimated is not buildable in
15 weeks with 2 engineers and a half designer."* Honest estimate for the MVP as written:
**26–32 weeks** — roughly 2×.

Their summary of the pattern: *"The doctrine is stated, then not engineered. Doc 02 declares an
inventory that infers consumption; doc 05 contains no consumption inference and no quantity
model. Doc 04 draws screens whose data does not exist in the doc 05 schema."*

### B1 — "Consumption is inferred" has no mechanism (severity: critical — their #1)
Doc 05 models **spoilage**, not consumption. The only consumption signals are a user tap, the
weekly sweep, and elapsed time. So "inference" collapses to *"assume it's gone at 130% of the
window"* — **a timer, not an inference**.

Compose that with the alert band (80–130% of window) and the result is damning:

> **The design fires alerts precisely in the window where the item is most likely already eaten.**
> The user bought spinach Saturday, ate it Monday, and gets a Wednesday notification telling
> them to rescue spinach that no longer exists.

We set a counter-metric of ≤20% stale alerts. They *"would bet heavily on 40–55% in a real
beta"* — and every one is exactly the trust-destroying event this plan was written to prevent.

**Their fix, and it is the best idea either reviewer produced:** model consumption from
**repurchase cadence**, which receipts give you *for free*. If a household buys milk every six
days, the milk is gone by day six regardless of shelf life. The at-risk score must become
`P(still present) × P(spoiling soon)`, suppressing the alert below ~0.6 presence.
**This signal was not in the plan at all.**

### B2 — Quantity and units are unmodelled, and three shipped screens depend on them
`ITEM` has no quantity, unit or pack size.
- `BROCCOLI CROWNS 1.2 LB` → the receipt's weight is discarded.
- Partial consumption is inexpressible, so the only action is binary Used/Gone — *"which forces
  the user to lie, and the lie trains your priors."*
- Doc 04 renders "🥚 Eggs 6 left" and "🥛 Milk plenty". **Neither string is derivable from the
  schema.** The don't-buy list — a P1 and a *paid* feature — is therefore not implementable.

Three more specific bugs:
- **`opened_on` missing.** A `bool opened` cannot support a ×0.35 multiplier on *remaining* life.
  Milk opened on day 5 of a 10-day window is arithmetically undefined.
- **`storage_changed_at` missing.** "Freeze it" claims to reset the clock; with a bare enum,
  freezing 8-day-old broccoli is indistinguishable from freezing fresh.
- **`date_label_type` missing.** UK launch. **"Use by" (safety) vs "best before" (quality) is
  *the* distinction**, it is legally loaded, and the entire safety carve-out hinges on it.

### B3 — The unit-cost model is wrong in the direction that kills the company
- **OCR price:** $0.01–0.03/receipt is at or below volume-committed pricing. At 50k docs/month
  we are a small account; realistic is **$0.04–0.08 — 3–5× our line item.**
- **The real error: cost is per *household*, revenue is per *paying* household.** At 6% conversion:

| Assumption | Monthly revenue | Monthly COGS | Gross margin |
|---|---|---|---|
| Our $0.01/receipt, free users max 4 scans | £1,794 | ~£650 | **64%** |
| Realistic $0.06/receipt, free users avg 1.5 | £1,794 | ~£1,210 | **33%** |
| Realistic $0.06/receipt, free users max 4 | £1,794 | ~£2,320 | **negative** |

> *"The claimed >93% appears under no assumption I can construct. 94% of your users are pure
> COGS with zero revenue."*

- **The most expensive endpoint in the system has no authentication.** "No account wall before
  value" means receipt OCR is available with no identity. *"Free-tier abuse isn't a risk here —
  it's the default configuration."* Anyone can use Crisper as a free receipt-OCR API.
- **Bootstrapping is backwards.** 15% LLM fallback assumes a mature dictionary; **at launch the
  dictionary is empty and fallback is ~100%.** Costs peak exactly when cash is scarcest — and
  our cost gate sat at month 9, after launch.

### B4 — The learning loop is statistically closed on its own output
- **Right-censoring ignored.** "Used on day 6" means shelf life **≥ 6 days**, not = 6. We are
  fitting *time-to-consumption* and calling it *time-to-spoilage*.
- **The loop is self-confirming.** We warn at day 8 → user cooks at day 8 → we record 8 →
  we warn at day 7 → repeat. *"There is no exogenous variation anywhere in this design"*, so the
  estimator converges toward warning about everything immediately **while the metric looks like
  it is improving.**
- **`w = n/(n+5)` is a magic constant, not shrinkage.** Real shrinkage weights by variance ratio.
  At n=6, w≈0.55 — six confounded, censored observations outvote the global rule.
- **The schema cannot store what the model needs**: no variance, so no principled weight and
  **no uncertainty band — which is the product's central promise.**
- **R4 AC4 is circular**: validating against FoodKeeper, which is the training source.

### B5 — iOS push will confound the retention gate, and the drawn notification cannot exist
- **Hard contradiction:** R5 AC3 and §4.9 require two lock-screen action buttons. **Safari Web
  Push does not support notification action buttons.** Doc 04 draws a notification that cannot
  exist on ~half the target market.
- **The 40% trigger is above what anyone achieves.** iOS has no install-prompt API; observed
  custom-prompt install rates are 5–20%. **~35–45% of the total user base never receives the
  mechanic doc 04 calls "the product."**
- **The measurement timing costs us the company:** G2 lands Feb 2027, native decision month 6,
  native build August 2027. *"You will measure your existential retention gate on a population
  where a large minority never got push"* — then either kill a working product for a platform
  reason, or pass on Android-skewed data and get surprised at launch.
- "One engineer-month" for the native shell is really **2–3**.

### B6 — Selected smaller findings (all actioned or logged)
**Data/schema:** the learned dictionary — *"the compounding asset"* — **has no table in the ERD**;
no `RECEIPT_LINE`, so a bad parse cannot be audited, diffed, retrained on, or scored for
production F1; event sourcing is half-done (mutable state *and* an append-only log, with no
stated invariant); append-only events vs GDPR erasure unaddressed; LWW sync specified with no
`updated_at`, no version vectors — *"two members doing the Sunday sweep on two phones produces
lost updates"*; **"multi-tenancy at the model layer" is self-refuting** (a Rails `default_scope`
*is* convention, and background jobs have no session — use Postgres RLS); `PRODUCT`/`CATEGORY`
rules are global and unversioned, so **recategorising a product silently re-dates live food in
every household**; the notification cap is called an invariant but has **no durable storage** —
a Redis flush voids it.

**Freshness:** **`freezer ×8` is structurally wrong** — frozen chicken is ~9 months, not 16 days;
freezer life is a *lookup*. `opened ×0.35` as a global constant is wrong in both directions.
`p50*0.8` invents percentiles from FoodKeeper's published *ranges*. **FoodKeeper is US guidance
for a UK launch** — different categories, different date-label law; the "curated top-200 UK
perishables table" is *"a person-month of food-science-adjacent research, unbudgeted."*
**Open Food Facts is ODbL** — share-alike may attach to a derived database, directly at odds
with treating the dictionary as a proprietary moat. Get a legal read.

**Parsing:** **"85% item F1" is undefined and therefore unfalsifiable** — per line or per item?
Is "Broccoli" vs "Broccoli crowns" a match? Doc 05's gate and doc 03's AC2 are *different
metrics*. The two gates trade off (you hit 95% non-food suppression trivially by dropping
aggressively, destroying recall) and nobody named the operating point. The eval set will be
**biased optimistic** — team-collected receipts are flatter and better-lit than one fished out
of a bag with a wet chicken; ≥40% must come from diary households. **n=20 per retailer is
underpowered.** Silently dropping food lines **is** invisible drift — show "3 lines we couldn't
read". No merchant classification (what happens on a Boots or restaurant receipt?).
**Retro-capture unhandled:** people scan days late, so `acquired_on` comes from the receipt date
and **an item can be born already at-risk**.

**Ops:** *"The failure mode of the whole system is silence, which is also the designed happy
path."* If the decay pass dies or push subscriptions expire en masse, **the product is invisibly
dead and no user will report it.** Needs a synthetic canary household and an SLO on alert volume.
The "nightly" pass is really 24+ timezone-sharded passes plus a separate local-17:00 scheduler.

**Legal/privacy:** **the DPIA is scheduled after the processing it assesses** — receipts are
processed from beta start (Dec 2026), DPIA was set for Feb 2027; GDPR Art. 35 requires it prior.
**The privacy promise is false as written**: sensitive lines are still transmitted to a
third-party OCR vendor and still visible in the stored image. **Check the OCR vendor's data-use
terms** — several reserve rights to train on submitted documents outside enterprise tiers.
International transfer needs SCCs/UK IDTA. **The learned dictionary is a poisoning *and safety*
vector**: any user can globally rename any retailer product, and *"remap a high-risk item into a
low-risk category and the safety carve-out silently disappears for every future user — someone
eats spoiled chicken because a stranger edited a string."*

**Gmail is an unmodelled calendar-time critical path:** restricted scopes require a **CASA Tier
2/3 assessment, ~$3k–15k and 4–12 weeks of calendar time**, annually re-verified. We budgeted 28
days of engineering. Apple Mail has no API at all.

**Business:** G2 at n=100 has a **±9.5pp CI** — *"you are making a company-ending decision on
noise."* G1 at n=20 is ±21pp, unblinded, incentivised, and measures the Hawthorne effect without
a control arm. Per-head burn declines 40% across the year — under-modelled by **£100–150k**.
**No marketing line at all**, no analytics infra, no eval-set maintenance, **no admin/support
tooling** despite "human-in-loop for the first 1,000 users" implying up to 5,000 receipts/month
of human review with nobody assigned. **The SEO thesis is dated** — "how long does broccoli last"
is exactly the query class AI Overviews answers without a click. **Four retention bars and three
conversion bars across the docs, with no source of truth.** Email import is P0 in the PRD, in the
MVP diagram, and in Phase 2 of the roadmap — *three documents, three answers*. Phase 0 is four
weeks in prose and six in the gantt, and the parser spike starts before the eval set finishes.

### B7 — Their cut list to ship ~6 weeks sooner
Voice capture entirely (−3 wks) · OAuth email import, ship forward-address only (−4 wks + removes
the CASA critical path) · shelf-photo capture (−2 wks) · the notification ranking/timing engine,
ship fixed 17:00 + a durable counter (−2 wks) · per-household learning (−4 wks) · tablet and
desktop layouts (−1.5 wks) · dark mode (−0.5 wk).

And **add** three cheap things: an email fallback alert channel (1 day), rate-limiting and
lightweight identity on the OCR endpoint (2 days), and **the repurchase-cadence consumption
signal (1 week — the highest-leverage missing piece in the entire architecture).**

---

## Part C — What changed in response

### Accepted and applied to the documents

| # | Finding | Change made |
|---|---|---|
| 1 | Consumption inference had no mechanism (B1) | **Repurchase-cadence consumption model added as a v1 P0.** At-risk score is now `P(still present) × P(spoiling soon)`; alerts suppressed below 0.6 presence. [05 §5.4b](05-technical-architecture.md), [03 R4b](03-product-strategy-prd.md) |
| 2 | Missed captures unmodelled (A2) | New §2.4b on false negatives; **capture compliance** and **end-to-end alert precision** added as first-class metrics. [02 §2.4b](02-ux-behavioural-research.md) |
| 3 | Quantity/units/opened_on/storage_changed_at/date_label_type missing (B2) | All added to the schema, plus a `PARTIAL_USE` event. [05 §5.3](05-technical-architecture.md) |
| 4 | Cost model wrong (B3) | Recomputed **per paying household** with realistic OCR pricing and a cold-dictionary bootstrap phase; margin restated honestly. [05 §5.8](05-technical-architecture.md) |
| 5 | Unauthenticated OCR endpoint (B3) | Device-bound token + rate limits before the first OCR call, pre-beta. [05 §5.6](05-technical-architecture.md) |
| 6 | Learning loop self-confirming and censored (B4) | Cut from v1. When it returns: survival model with censoring, variance in the schema, and **randomised alert-day jitter** for exogenous variation. [05 §5.4c](05-technical-architecture.md) |
| 7 | Safari has no notification actions (B5) | Notification redesigned to **one action**; two-button treated as an Android/native enhancement; **email fallback channel added to v1**. [04 §4.9](04-ui-screens-flows.md), [03 R5](03-product-strategy-prd.md) |
| 8 | iOS push confounds G2 (B5) | Native decision moved **before** G2; G2 stratified by platform and push status. [06 §6.5](06-business-plan-roadmap.md) |
| 9 | Phase 0 asks the wrong question (A9) | **Phase 0 inverted: a 6-week, ~£15k human concierge test comes first**, measuring capture compliance and rescue-on-prompt. Parser spike runs alongside, not first. [06 §6.4](06-business-plan-roadmap.md) |
| 10 | Free/paid line backwards (A5, B6) | Redrawn: **free contains the habit** (unlimited capture, alerts, list, one partner); **paid contains the leverage**. Annual-first pricing; lifetime option added. [06 §6.2](06-business-plan-roadmap.md) |
| 11 | Retention undefined, wrong cohort, four competing bars (A3, B6) | Single retention ladder, defined as *value received* not app opens, gated on a cold-acquired cohort, with CI stated. [03 §3.7](03-product-strategy-prd.md), [06 §6.5](06-business-plan-roadmap.md) |
| 12 | LTV/CAC arithmetic (A3) | Recomputed at 10%/mo churn, net of store fees and VAT. [06 §6.7](06-business-plan-roadmap.md) |
| 13 | Scope 2× under (B7) | v1 cut list applied: voice, shelf photo, OAuth email, ranking engine, per-household learning, tablet/desktop, dark mode. |
| 14 | Gmail CASA critical path (B6) | v1 is **forward-to-address only**. OAuth mailbox access deferred to v3 with the assessment cost and calendar time named. |
| 15 | DPIA after processing (B6) | Moved into Phase 0. |
| 16 | Dictionary poisoning / safety vector (B6) | Corrections per-household by default; global promotion needs k≥5 independent households; **a correction may never downgrade `high_risk` without human review**. |
| 17 | Fabricated charts, laundered citations, stopwatch fiction (A7) | Every invented figure now carries an explicit "illustrative, not measured" caveat; competitor-blog citations labelled non-independent; timing annotations relabelled as targets. |
| 18 | Freezer ×8, opened ×0.35, invented percentiles, US data for UK (B6) | Freezer is a lookup table; opened is a per-rule duration; FoodKeeper ranges stored as ranges; **UK shelf-life curation budgeted as a person-month**. |
| 19 | Missing infra/ops/marketing lines (B6) | Canary household + alert-volume SLO; admin/support tooling; analytics; eval-set maintenance; marketing budget — all added to the plan and the burn. |
| 20 | Missing screens (A6) | Onboarding, correction, paywall, holiday mode, dedupe and partial-use states added to the doc-4 backlog. |

### Accepted in principle, deliberately not yet acted on

| Finding | Position |
|---|---|
| **Reframe the wedge to "what to cook tonight"** (A1) | The strongest strategic idea in either review, and it may well be right. But it changes the company, not the plan — and the concierge test in the new Phase 0 is designed to surface exactly this: their prediction is that engaged households stayed for *what to cook*, not *what they owned*. **We test it rather than assume it either way.** |
| **Selection inverts the value** (A1) | Accepted as a real, unfixable-by-UX demand-side risk. Phase 0 now recruits *high-waste* households specifically, not enthusiastic ones. |
| **Fango is the primary disconfirmation** (A1) | Accepted; doc 1 corrected. A teardown of Fango's actual retention is now a Phase 0 task. |
| **Don't raise £750k–1M against a £2–3M ARR ceiling** (A7, and their fund verdict) | Legitimate. The revised recommendation is a **£150–250k pre-seed against the concierge test**, with the larger raise contingent on what it shows. |
| **Open Food Facts ODbL share-alike** (B6) | Needs a lawyer, not a document edit. Logged as a Phase 0 blocker before any dictionary work. |
| **The SEO channel is dated** (B6) | Accepted. Acquisition strategy needs rework; no credible replacement identified yet, which is itself a finding. |

### Rejected, with reasons

| Finding | Why not |
|---|---|
| Cut the weekly sweep as doctrine-breaking (A6) | The doctrine says *never require* maintenance. The sweep is optional, finishable, and only fires on genuine model uncertainty. It stays — but it is now measured: if sweep completion is under 30%, it is dead weight and gets cut. |
| Cut the Kitchen tab entirely (A6) | Users need *somewhere* to look things up, and its absence would push that job onto Today. Demoted further, not removed. |
| Abandon notification restraint for presence (A4) | We accept the *diagnosis* — a variable, weekly, external cue is weak habit substrate — but the answer is **non-interruptive presence** (widget, lock-screen glance, a voluntarily-opened shopping list), not more interruptions. Restraint on interruption stands. |

### What the German re-base changed about these findings

| Finding | Effect of moving to Berlin/Germany |
|---|---|
| **A2 — missed captures** | ✅ **Materially improved.** The Belegausgabepflicht hands every German shopper a receipt by law, several times a week. This is the best answer available to "no UI fixes forgetting" |
| **A2 — email import as the fix** | ❌ **Weakened.** German online grocery is only ~2.4% of retail volume, so email import is near-useless nationally. Paper photo is the primary path, not the fallback |
| **B3 — cost model** | ➖ Unchanged in shape; re-denominated in €. 19% VAT slightly better than 20%, and **web-first PayPal/SEPA checkout avoids the 15–30% store cut**, which is a real German-market margin gain |
| **A5 — free/paid line** | ➖ Redrawn as recommended, and re-priced to €29/yr. ⚠️ **Harder in Germany**: foodsharing.de and a free BMLEH app anchor the reference price at zero |
| **A3 — retention cohorts** | ⚠️ **A new confound.** Berlin is 50% single-person households against 2.01 persons nationally, so cohorts *must* be cut by household size or the singles cohort will flatter every number |
| **A1 — selection inverts the value** | ⚠️ **Sharper in Berlin than the UK.** Phase 0 now recruits in Marzahn-Hellersdorf, Spandau and Reinickendorf, ≥16 of 25 households with children |
| **A7 / B6 — legal and evidence discipline** | 🔴 **Heavier.** DSGVO plus BDSG, the Kündigungsbutton requirement, UWG substantiation enforced by competitor *Abmahnung*, and Verbrauchsdatum vs MHD as a safety-critical distinction |
| **The raise** | ✅ **Improved.** EXIST / Berlin Startup Stipendium make ~€110k of the round non-dilutive, and IBB's B# convertible defers the valuation argument the DCF cannot win |

### Postscript — what the German re-base and doc 12 resolved

| Their finding | Status now |
|---|---|
| **B3 — the cost model is wrong in the direction that kills the company** | ✅ **Resolved, and reversed.** Removing the OCR vendor for VLM-first extraction takes fully-loaded COGS from €0.75 to €0.11 per paying household/month, gross margin from 66% to ~95%, and LTV/CAC with the hand-off from 2.4× to **3.1×** — the first version to clear the threshold. Their diagnosis (cost per household vs revenue per *paying* household) was correct and is what made the error visible |
| **A "VLM has no confidence scores" problem this would have created** | ✅ **Pre-empted** by the German receipt checksums — the Summe total and the A/B VAT class (the TSE QR |
| **B5 — iOS push and the native shell** | ⚠️ Unchanged, and now **reinforced**: auto-capture (ML Kit / VisionKit) is a second independent reason for the shell, since the web Shape Detection API is broken on iOS 18 |
| **A1 — "is the thesis right at all?"** | ⚠️ **Still open, and still the real risk.** No amount of cheaper parsing answers it. The Berlin concierge test does |

### The one-line summary of this review

Both reviewers independently reached the same shape of conclusion: **the strategy documents are
stronger than the engineering ones, and the plan's confident prose was outrunning its evidence.**
The single most valuable finding is B1 — *the trust cliff we diagnosed in doc 1 is not defended
by anything in doc 5* — and the single most valuable recommendation is A9: **spend £15k and six
weeks on a human concierge before spending £620k on software.**
