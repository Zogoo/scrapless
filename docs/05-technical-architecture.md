# 5. Technical Architecture

> **Launch market: Berlin → Germany → DACH** ([doc 11](11-germany-berlin-market.md)). The product
> is German-first: German UI strings, German receipt abbreviations, German date-label semantics.
>
> **Stated assumption:** this plan lives in a Ruby workspace, so the reference stack is
> **Rails 8 + Hotwire**. The architecture is stack-agnostic where it matters; §5.9 lists the
> alternative if the team is stronger in TypeScript. Flagging this rather than silently
> assuming it.

---

## 5.1 System overview

```mermaid
flowchart TB
    subgraph CLIENT["Client — responsive PWA"]
        UI[Hotwire / Turbo views<br/>+ Stimulus controllers]
        SW[Service worker<br/>offline cache: inventory, don't-buy]
        CAM[Camera / MediaRecorder<br/>Web Speech API]
        IDB[(IndexedDB<br/>optimistic local state)]
    end

    subgraph EDGE["Edge"]
        CDN[CDN + static assets]
        WAF[Rate limit / WAF]
    end

    subgraph APP["Application — Rails 8"]
        API[REST + Turbo Streams]
        AUTH[Auth · household sessions]
        INV[Inventory service]
        FRESH[Freshness engine]
        NOTIF[Notification scheduler<br/>budget enforcement]
    end

    subgraph WORK["Background — Solid Queue"]
        OCR[Receipt pipeline]
        EMAIL[Email ingest poller]
        DECAY[Nightly decay pass]
        LEARN[Household prior updater]
    end

    subgraph DATA["Data"]
        PG[(PostgreSQL<br/>households · items · events)]
        REDIS[(Redis / Solid Cache)]
        BLOB[(Object store<br/>receipt images, TTL 30d)]
    end

    subgraph EXT["External"]
        VLM[Vision LLM<br/>reads the receipt end-to-end<br/>~$0.0008–0.002 per receipt]
        LLM[Stronger model<br/>second pass, ~15%]
        OFF[Open Food Facts]
        FK[German shelf-life table<br/>BMLEH · Verbraucherzentrale<br/>FoodKeeper as cross-check only]
        PUSH[Web Push / APNs]
        MAIL[Gmail API / IMAP /<br/>forward-to inbox]
    end

    UI <--> CDN --> WAF --> API
    CAM --> API
    SW <--> IDB
    API --> INV & AUTH
    INV --> PG
    API --> REDIS
    OCR --> VLM --> LLM
    OCR --> BLOB
    EMAIL --> MAIL
    FRESH --> FK & OFF
    DECAY --> FRESH
    NOTIF --> PUSH
    LEARN --> PG
    APP --> WORK

    style FRESH fill:#e8eaf6,stroke:#3949ab,stroke-width:2px
    style OCR fill:#fff4e5,stroke:#ef6c00,stroke-width:2px
```

---

## 5.2 The receipt pipeline — VLM-first

> ⚠️ **Rewritten.** This section previously specified a commercial receipt-OCR vendor
> (Veryfi / Mindee / Taggun / Tabscanner) with an LLM only as a fallback. **That was a 2023
> architecture.** Full evidence and costings: [doc 12](12-technical-research-capture.md).
> Accuracy here still determines whether the product works at all (Risk R1).

```mermaid
flowchart TD
    IMG[Receipt photo] --> PRE["Client: downscale to long edge ~2048<br/>deskew · JPEG q80 — saves tokens"]
    PRE --> QR["Client: BarcodeDetector → TSE QR<br/>unique receipt id (dedupe) + exact timestamp<br/>⚠️ contains NO amounts"]
    QR --> VLM["Vision model, temperature 0, pinned version<br/>structured JSON schema:<br/>merchant · date · lines[raw_text, name, qty, unit, price, vat_class]<br/>totals[sum, by_vat_class]"]
    VLM --> C1{"CHECKSUM 1<br/>lines sum to the printed Summe?"}
    C1 -->|no| LOW["Low confidence:<br/>surface the whole receipt for review"]
    C1 -->|yes| C2{"CHECKSUM 2<br/>per-VAT-class subtotals match<br/>the MwSt block?"}
    C2 -->|no| PART["Partial: surface only<br/>the mismatched class"]
    C2 -->|yes| HIGH["High confidence:<br/>auto-accept, collapsed in the UI"]
    C2 --> VAT["A = 7% → almost always food<br/>B = 19% → almost always non-food"]
    VAT --> SUP["Non-food suppression<br/>without a trained classifier"]
    HIGH & PART & LOW --> DICT2["Dictionary lookup on raw_text<br/>→ canonical product"]
    DICT2 -->|unresolved ~15%| STRONG[Second pass, stronger model]
    DICT2 --> SHELF[Freshness engine]
    STRONG --> SHELF
    STRONG -.->|user correction| DICT[(Learned dictionary<br/>per chain, global)]
    DICT -.->|improves, and skips the second pass| DICT2
    style VAT fill:#e7f6ec,stroke:#2e7d32,stroke-width:2px
    style HIGH fill:#e7f6ec,stroke:#2e7d32
    style LOW fill:#fdecea,stroke:#c62828
    style DICT fill:#e7f6ec,stroke:#2e7d32,stroke-width:2px
```

### Why this replaced the vendor

| | Commercial OCR vendor | **VLM-first** |
|---|---|---|
| Cost per receipt | $0.04–0.08 negotiated | **~$0.0015–0.002 blended** — roughly **40× cheaper** |
| Vendor concentration risk | Real; needed dual-sourcing | **Gone** |
| Processors in the DSGVO chain | Two (OCR + LLM) | **One** |
| Per-field confidence scores | ✅ provided | ❌ **not provided** — see below |

### The accuracy case, not only the cost case

| Approach | Extraction accuracy |
|---|---|
| **Vision-first extraction** | **92.7%** |
| Parsed-text OCR pipeline | 64.0% |
| LLM extraction on structured fields | **97–99%** |
| OCR alone on structured fields | 85–95% |

⚠️ **The catch, and it points at a v2 decision.** **Specialised document models hallucinate far
less than general-purpose VLMs — 93.2% against 72.6–85.0%.** That is the argument for migrating to
a **self-hosted, open-weight document-OCR specialist in v2**, which would resolve three problems in
one move: lower hallucination (R13), **EU data residency** without a transfer impact assessment,
and **no model-deprecation exposure** (R14). Ship the hosted VLM in v1; plan the migration.

**What survives:** the learned chain dictionary is *more* valuable now, not less — it is what lets
us skip the second pass, and it still improves with every correction.
**What dies:** the OCR vendor, the dual-sourcing requirement, the vendor concentration risk, and
the "$0.01–0.03 list-price fantasy" the engineering reviewer identified.

### ⚠️ The risk moved — it did not disappear

We traded a **cost** risk for an **accuracy** risk, and the second is more dangerous because it is
**silent**.

| Risk | Why it matters here | Mitigation — **v1, not bolted on** |
|---|---|---|
| **No per-field confidence** | Our whole doctrine — uncertainty bands, what the sweep asks about, what surfaces in review — depends on knowing what we are unsure of. A VLM returns fluent JSON with no error bars | The two German checksums below |
| **Hallucination** | A VLM will invent a plausible line on a faded thermal receipt. **Worse than an OCR error, because it is confident and reads correctly** | Checksums catch price errors; **self-consistency** (two passes at temp 0, compare) catches name drift. At ~$0.0008/pass this is affordable |
| **No bounding boxes / provenance** | Harder to build `RECEIPT_LINE` and audit a bad parse | The model must return the **verbatim `raw_text`** beside the normalised name — that is the dictionary training pair, without needing coordinates |
| **Model deprecation** | Providers retire models. **The vendor used to absorb this** | Pin model versions; re-run the full 200-receipt eval on every model change. **A new standing ops cost** — see §5.10 |
| **Latency** | 3–10 s on a long receipt vs 1–2 s for OCR | Upload-and-dismiss with async completion — already required by the ≤30 s effort budget |
| **Non-determinism in CI** | Noisy eval gates | Temperature 0, pinned version, **prompt hash recorded with every eval run** |
| **DSGVO** | Receipt images to a model provider | Same class of problem as the vendor, but **one fewer processor**. Verify EU residency and zero-retention before beta |

### ⭐ Two German validation mechanisms that replace confidence scores

> ⚠️ **Corrected.** This was written as *three* mechanisms. The TSE QR code was checked and **is
> not a checksum** — see below. Two legally-guaranteed checks is still more than any other market
> offers.

**This is where the German launch market pays off a second time. German receipts carry their own
error checking** — exactly what a VLM lacks.

1. **The Summe checksum.** Every receipt contains its own answer key. If the extracted lines don't
   sum to the printed total, the extraction is wrong — **known deterministically, for free.**
   This single check recovers most of what per-field confidence gave us.
2. **The A/B VAT class as a free food classifier.** German receipts mark each line `A` = 7%
   (reduced rate, *Grundnahrungsmittel*) or `B` = 19% (standard), and the law requires the receipt
   to show what was taxed at which rate. **A legally-mandated per-line food signal on every Bon**,
   which largely delivers [R1-AC2](03-product-strategy-prd.md)'s ≥95% non-food suppression for free.
   ⚠️ *A strong prior, not a rule: alcohol, many beverages and some luxury foods are 19%; books and
   plants are 7%. High-weight feature, not a hard filter.*
3. ⚠️ **CORRECTION — the TSE QR is *not* a totals checksum.** Researched in
   [§12.1c](12-technical-research-capture.md#121c-the-tse-qr-code--what-it-actually-contains):
   the payload carries **only** the TSE serial, transaction number, signature counter, timestamps
   and cryptographic signature. **No line items, no totals, no VAT-rate amounts.** The amounts are
   legally required on the *printed* receipt (§6 KassenSichV) — which is what makes checksums 1
   and 2 work — but they are printed text, not decodable data.
   **What the QR is still worth:** a globally unique receipt id (**free, exact duplicate
   detection**) and an authoritative purchase timestamp, which fixes the **retro-capture** problem
   noted below, where a receipt photographed days late can make an item *born already at-risk*.

### Build order

1. **Client-side preprocessing** — downscale, deskew, JPEG q80. Cheap, and it directly cuts tokens.
2. **`BarcodeDetector`** for the TSE QR — free, and better supported than the rest of Shape
   Detection. **Not for validation** (it carries no amounts): for duplicate detection and an exact
   purchase timestamp.
3. **VLM call** with a pinned model, temperature 0 and a structured JSON schema.
4. **Checksums 1–2** (Summe, per-VAT-class subtotals), then dictionary lookup, then a second pass
   only on the residue (~15%).

**Evaluation harness before any UI work:** 200 real German receipts across the **10 chains that
cover ~80% of German grocery spend** (Edeka, REWE, Lidl, Aldi Nord, Aldi Süd, Kaufland, Penny,
Netto, dm, Rossmann), hand-labelled, **≥40% photographed by real households in their own kitchens**.

> 🇩🇪 **Two German specifics that shape this pipeline.**
> **(1) The Belegausgabepflicht guarantees the input.** Every till transaction issues a receipt by
> law, so paper-photo capture is the *primary* path in Germany, not a fallback — and email import
> is near-useless nationally, because German online grocery is only ~2.4% of retail volume.
> **(2) Edeka is a federation of independent retailers with non-uniform receipt formats.** It is
> the largest chain (€84.7bn) *and* the hardest to template. Budget for Edeka to take as long as
> the next three chains combined, and stratify the eval set to prove it.

## 5.3 Data model

```mermaid
erDiagram
    HOUSEHOLD ||--o{ MEMBERSHIP : has
    USER ||--o{ MEMBERSHIP : joins
    HOUSEHOLD ||--o{ CAPTURE : records
    CAPTURE ||--o{ ITEM : produces
    HOUSEHOLD ||--o{ ITEM : holds
    ITEM ||--o{ ITEM_EVENT : logs
    PRODUCT ||--o{ ITEM : "identifies (nullable)"
    PRODUCT }o--|| CATEGORY : belongs_to
    CATEGORY ||--o{ SHELF_LIFE_RULE : defines
    HOUSEHOLD ||--o{ HOUSEHOLD_PRIOR : learns
    HOUSEHOLD ||--o{ REPURCHASE_STAT : "reveals cadence"
    HOUSEHOLD ||--o{ NOTIFICATION : "budget ledger"
    CAPTURE ||--o{ RECEIPT_LINE : "raw OCR, audited"
    RECEIPT_LINE ||--o| ITEM : "resolves to"
    PRODUCT ||--o{ DICTIONARY_ENTRY : "learned aliases"

    HOUSEHOLD { uuid id string name string timezone jsonb alert_prefs }
    CAPTURE { uuid id enum source string merchant date purchased_on float parse_conf uuid image_key }
    ITEM { uuid id string display_name uuid product_id numeric quantity enum unit float qty_confidence enum storage timestamp storage_changed_at date acquired_on date window_start date window_end float confidence enum state date opened_on enum date_label_type date date_label_value uuid rule_id int rule_version }
    ITEM_EVENT { uuid id enum kind timestamp at uuid actor_id jsonb meta }
    PRODUCT { uuid id string gtin string canonical_name uuid category_id }
    CATEGORY { uuid id string name bool high_risk }
    SHELF_LIFE_RULE { uuid id uuid category_id enum storage int days_p50 int days_p90 bool opened_variant }
    HOUSEHOLD_PRIOR { uuid id uuid category_id float observed_days_p50 float variance int n_censored int n_uncensored }
    RECEIPT_LINE { uuid id uuid capture_id int line_no string raw_text enum vat_class numeric line_price string parsed_name enum parse_path float checksum_state uuid item_id }
    DICTIONARY_ENTRY { uuid id string merchant string raw_text uuid product_id int distinct_household_votes enum promotion_state bool touches_high_risk }
    NOTIFICATION { uuid id uuid household_id string iso_week int slot timestamp sent_at enum outcome }
    REPURCHASE_STAT { uuid id uuid household_id uuid category_id float median_interval_days int n_intervals }
```

**Key modelling decisions**

| Decision | Why |
|---|---|
| `ITEM.window_start` / `window_end` rather than one `expires_on` | Encodes uncertainty structurally. It is then *impossible* for the UI to render a fake precise date. This is architecture enforcing a product promise. |
| `ITEM.confidence` float | Drives auto-retirement and whether the sweep asks about it |
| `ITEM_EVENT` append-only log | Every rescue/waste/correction is training data; state is derived. Also gives us honest analytics. |
| `HOUSEHOLD_PRIOR` per category | Personalised shelf life — the retention moat. A household that eats spinach in 4 days should stop being warned at day 6. |
| `PRODUCT` nullable on `ITEM` | Loose broccoli has no GTIN and must still be a first-class item. Barcode-first schemas can't express this — that's a root cause of competitor failure. |
| Household is the tenant, not user | Food belongs to a home. Enforced by **Postgres row-level security** with a session GUC set in an `ApplicationJob` callback — *not* a Rails `default_scope`, which is convention and leaks through raw SQL and background jobs that have no session |
| `quantity` + `unit` + `qty_confidence` | ⚠️ *Added after review.* Without it, `BROCCOLI CROWNS 1.2 LB` discards the weight, partial consumption is inexpressible, and the don't-buy list ("6 eggs left", "milk plenty") is **not implementable**. Low confidence is fine — the UI can say "some spinach", which is consistent with the uncertainty doctrine |
| `opened_on` (a date, not a bool) | The ×0.35 multiplier applies to *remaining* life from the opening date. With a bool, milk opened on day 5 of a 10-day window is arithmetically undefined |
| `storage_changed_at` | "Freeze it" claims to reset the clock. Without a timestamp, freezing 8-day-old broccoli is indistinguishable from freezing fresh |
| `date_label_type` + `date_label_value` | **German launch: "Verbrauchsdatum" (safety — never extended) vs "Mindesthaltbarkeitsdatum/MHD" (quality — may extend) is *the* legally loaded distinction**, and the entire safety carve-out depends on it |
| `rule_id` + `rule_version` snapshotted on `ITEM` | Shelf-life rules are global. Without a snapshot, recategorising one product **silently re-dates live food in every household** and can fire notifications. Biggest migration hazard in the system |
| `RECEIPT_LINE` keeps the **verbatim `raw_text`** | Without it a bad parse cannot be audited, diffed against a user correction, retrained on, or scored for production F1. ⚠️ *Now doubly required: a VLM returns no bounding boxes, so verbatim raw text is the only provenance we get — and it is the dictionary training pair* |
| `RECEIPT_LINE.vat_class` (A/B) | The legally-mandated German per-line food signal. Drives non-food suppression and is a checksum input |
| `RECEIPT_LINE.checksum_state` | Which of the two German checksums passed (Summe reconciliation, VAT-class subtotals). **This is our confidence score** now that the OCR vendor's per-field confidence is gone |
| `CAPTURE.parse_conf` is now *derived from checksums*, not vendor-reported | The architecture must not pretend to a confidence it no longer receives |
| `DICTIONARY_ENTRY` is a real table | It is described as the compounding asset and was **absent from the original ERD** |
| `NOTIFICATION` ledger with `UNIQUE(household_id, iso_week, slot)` | The 3/week cap is called an invariant; invariants need durable storage. A Redis counter is voided by a cache flush |
| `ITEM_EVENT` adds a `PARTIAL_USE` kind | Binary Used/Gone forces the user to lie, and the lie trains the priors |

> **Event-sourcing decision (was previously half-done):** `ITEM_EVENT` is an **append-only audit
> log**, and `ITEM` is the source of truth for current state. It is explicitly *not* a projection.
> That resolves the ambiguity, and it keeps GDPR erasure tractable — hard delete removes the
> household's rows outright rather than requiring crypto-shredding of an immutable log.

> **Sync decision (replaces last-write-wins):** LWW with no `updated_at`, no version vectors and
> an undefined client/server clock loses updates when two members sweep on two phones. Resolution
> is now **server-authoritative** with a `lock_version` per item; quantity changes are applied as
> **deltas**, never absolute writes, so two concurrent decrements both land.

---

## 5.4 The freshness engine

```
window = f(base_shelf_life, storage, opened, household_prior, printed_date)

1. printed_date read from label      → window = [printed-2d, printed+3d], conf 0.95
2. GTIN → product → category rule    → window = [p50*0.8, p90],           conf 0.80
3. text → category rule (FoodKeeper) → window = [p50*0.7, p90],           conf 0.60
4. unknown                           → global fallback by storage,        conf 0.30

then:  storage         →  FREEZER IS A LOOKUP, NOT A MULTIPLIER
                          (frozen chicken ~9 months, not 8 x a 2-day fridge window)
       opened          →  per-rule remaining-life DURATION from opened_on,
                          not a global x0.35 constant
       date_label_type →  German: VERBRAUCHSDATUM (safety) clamps hard and is NEVER extended;
                          MINDESTHALTBARKEITSDATUM (quality) may extend
       high_risk       →  hard-clamp to printed date, never extend
```

Shelf-life base data for the **German** launch: a **curated German top-200 perishables table**
built from **BMLEH / Verbraucherzentrale** guidance as the spine, **Open Food Facts** for
GTIN → product → category, with **USDA FoodKeeper as a cross-check only**.

> 🇩🇪 **This is a bigger job than the original plan implied.** The GfK study for the BMEL shows
> **35% of avoidable German household waste is fresh fruit and vegetables and 13% is bread and
> bakery** — 48% in two categories with no barcode, no printed date, and the least reliable public
> shelf-life data. **The German curation is therefore a genuine person-month on the critical path**,
> not a footnote, and it is budgeted as such.

> ⚠️ **Open Food Facts is ODbL, and share-alike is a *schema* constraint.** Researched in
> [§12.5](12-technical-research-capture.md#125-open-food-facts-licensing--resolved-and-it-is-an-architecture-rule):
> *"If you combine data from Open Food Facts with other databases, the resulting database must be
> released as open data as well."* **So OFF must stay a separate, read-only lookup service — never
> merged into `PRODUCT` or `DICTIONARY_ENTRY`** — or the learned dictionary, our stated moat,
> becomes publishable. Store a GTIN reference, not copied OFF rows. Custom User-Agent and
> attribution are required. Cheap to design in now; expensive to retrofit later.
>
> ⚠️ **Corrections from review, plus the German re-base.** (1) FoodKeeper publishes **ranges** ("3–5 days"), not
> distributions — the original `p50 × 0.8` manufactured percentiles that don't exist. Store the
> source range and state plainly that the band is heuristic. (2) **FoodKeeper is US guidance and does not fit a German
> launch** — different categories, different products, and different date-label law
> (MHD/Verbrauchsdatum vs best-before/use-by). The German top-200 table is **a person-month of
> food-science-adjacent research**, now budgeted as such. (3) **Open Food Facts is ODbL.** Share-alike may attach to a derived
> database, which is directly at odds with treating the learned dictionary as a proprietary moat.
> **Legal read required before any dictionary work begins** — logged as a Phase 0 blocker.

---

## 5.4b Consumption inference — the missing mechanism

> ⚠️ **Added after senior review, and it is the most important change in this document.**
> The engine above models **spoilage**. The doctrine in doc 2 promises that **consumption is
> inferred**. As originally written there was no consumption model at all — "inference" collapsed
> to *"assume it's gone at 130% of the window"*, which is a timer. Composed with an alert band of
> 80–130%, **the design fired alerts precisely in the window where food is most likely already
> eaten**: bought Saturday, eaten Monday, notified Wednesday. That is the trust cliff doc 1
> diagnoses, undefended.

**The signal we were ignoring is free.** Receipts reveal *repurchase cadence*. If a household
buys milk every six days, the milk is gone by day six regardless of shelf life — and this costs
the user nothing.

```
P(still present at day d) = survival( d ; household repurchase interval for this category,
                                          quantity bought, household size )

at_risk_score = P(still present)  ×  P(spoiling within 48h)

ALERT only when  P(still present) ≥ 0.6   AND   at_risk_score above threshold
```

`REPURCHASE_STAT` accumulates median intervals per household × category from capture history
alone. Cold start falls back to a global cadence table by category and household size.

**Consequences**
- Alerts stop firing on food that is statistically already eaten — directly attacking the
  ≤20% stale-alert target the reviewer expected to land at **40–55%** without this.
- Presence probability is also what makes the sweep cheap: we only ask about items where
  `P(still present)` sits in the genuinely ambiguous 0.4–0.7 band.
- **Build this before the receipt parser.** It determines whether the parser matters.

## 5.4c Per-household shelf-life learning — deferred out of v1

Cut from v1 on review. Three defects had to be fixed before it is worth building:

1. **Right-censoring.** "Used on day 6" means shelf life **≥ 6 days**, not = 6. Fitting a median
   to Used events estimates *time-to-consumption* and calls it *time-to-spoilage*. Treat
   Used/Froze as **right-censored** and only Gone/spoiled as uncensored; fit a Weibull with
   censoring (about a week of work, and correct).
2. **Self-confirmation.** We warn at day 8 → the user cooks at day 8 → we record 8 → we warn at
   day 7 → repeat. With no exogenous variation the estimator converges toward warning about
   everything immediately, **while the metric appears to improve.** Fix: randomise the alert day
   by ±1–2 days for a small holdout slice. Cheap, and it is the difference between a learning
   system and a feedback oscillator.
3. **`w = n/(n+5)` is a magic constant.** Real shrinkage weights by variance ratio
   `σ²_between / (σ²_between + σ²_within/n)`, which requires `variance` in the schema — now added.
   At n=6 the old formula gave a household prior 55% weight on six confounded observations.

**Validation is no longer circular.** The old AC — "validate against FoodKeeper" — measured
nothing, because FoodKeeper *is* the training source. Replaced by: hold out 20% of categories
from the rule table and measure on those, plus ground truth from the Phase 0 diary study.

---

**Nightly decay pass** (Solid Queue cron): recompute states, mark ghosts, enqueue notification
candidates. O(items) — trivially cheap, runs in the household's local early morning.

---

## 5.5 Notification budget enforcement

The 3/week cap is a **server-side invariant**, not a UI preference — otherwise it will erode
under growth pressure from some future quarter's engagement target.

```mermaid
flowchart TD
    CAND[Candidate alerts<br/>from nightly pass] --> DEDUP[Group by household]
    DEDUP --> RANK[Rank by:<br/>value at risk × rescue likelihood × recency]
    RANK --> BUDGET{Sent this week<br/>< budget?}
    BUDGET -->|no| DROP[Drop — silence is fine]
    BUDGET -->|yes| WORTH{Top candidate<br/>worth interrupting?<br/>score > threshold}
    WORTH -->|no| DROP
    WORTH -->|yes| TIME[Schedule at learned<br/>decision time]
    TIME --> SEND[Send · 1 notification · ≤2 items]
    SEND --> OBS[Observe outcome]
    OBS -->|ignored ×2| LOWER[Lower budget for<br/>this household]
    OBS -->|tapped| HOLD[Hold cadence]
    style DROP fill:#e7f6ec,stroke:#2e7d32
```

Note the design bias: **the default path is to send nothing.** An alert must earn its way out.

---

## 5.6 Privacy & security

Receipts are among the most sensitive consumer data that exists — they reveal health,
religion, pregnancy, addiction, and income. This deserves more care than the category has
historically shown.

| Control | Implementation |
|---|---|
| Email scope | Read-only, single label/folder, or a forward-to address as the default (no mailbox access at all) |
| Receipt images | Encrypted at rest, **auto-deleted after 30 days**, never used for training without explicit opt-in |
| Non-food lines | Pharmacy, alcohol, and other sensitive line items **discarded at parse time, never persisted** |
| Data sale | Never. Written into the privacy policy and the ToS as a binding commitment. **In Germany this is worth more than anywhere else** — make it a headline claim, in German, on the landing page. If the business model ever requires it, we change the business model. |
| Retention | Full export + hard delete, self-serve, ≤30 days to complete |
| Auth | Passkeys first, magic link fallback. No passwords. |
| Multi-tenancy | Every query scoped by `household_id`; enforced at the model layer, not by convention |
| LLM calls | Zero-retention endpoints; item strings only, never full receipts with totals/payment data |
| **OCR endpoint identity** | ⚠️ *Added after review.* "No account wall before value" left **the most expensive endpoint in the system unauthenticated** — anyone could use Scrapless as a free receipt-OCR API. A device-bound token plus per-device and per-IP rate limits is required **before the first OCR call**, shipped pre-beta. Free-tier abuse was not a risk; it was the default configuration |
| **Dictionary poisoning** | ⚠️ Corrections are **per-household by default**; global promotion requires **k ≥ 5 independent households**; a correction may **never** downgrade `CATEGORY.high_risk` without human review; corrections are rate-limited and carry provenance for rollback. Without this, remapping a high-risk item into a low-risk category silently removes the safety carve-out for every future user |
| **Model-provider data-use terms** | ⚠️ *Rewritten with the VLM-first architecture.* There is now **one processor instead of two**, which is a genuine privacy improvement. But the claim *"never used for training"* still depends on contract terms — require **zero-retention endpoints and EU data residency** before beta, and record the commitment in the DPIA |
| **Honest scope of the privacy promise** | ⚠️ "Sensitive lines discarded at parse time" is true of *our database only* — they are still transmitted to the OCR vendor and still visible in the 30-day image. The promise must be worded to say exactly that |
| International transfer | EU receipt images to US OCR/LLM requires **SCCs plus a transfer impact assessment** — or an EU-resident vendor, which is the preferred answer here |
| **EU model residency** | ⚠️ *Vendor-specific and partly irreversible ([§12.1d](12-technical-research-capture.md#121d-eu-data-residency--constrains-the-vendor-choice)):* **OpenAI EU residency + zero retention can only be set on a *new* Project** — create it correctly on day one. **Vertex AI pins region per call, not per project** — so region pinning is a **DPIA line item** with an automated assertion, not an implementation detail. **Anthropic's direct API has no EU-only residency** — route via EU-scoped Bedrock or Vertex. The **EU AI Act has been broadly applicable since 2 August 2026** |
| Hosting | **EU region only.** German consumers are the most privacy-conscious in Europe; US-region storage of receipt images is a conversion problem as well as a legal one. Prefer an **EU-resident OCR vendor** even at a premium |
| Payments | **PayPal + SEPA Lastschrift on web checkout.** German card penetration is ~11% of online purchases — the lowest of any major Western economy — so card-only checkout would silently halve conversion, and app-store IAP is card-centric. Web-first also avoids the 15–30% store cut |
| Compliance | **DSGVO + BDSG**, and Germany's **Kündigungsbutton** requirement (a compliant one-click cancel for online subscriptions) before the paywall goes live. **DPIA moved into Phase 0** — receipts are processed from beta start, and Art. 35 requires the assessment *prior to* processing, not after |

> This is also a **differentiator**. "We never sell your shopping data" is a credible, checkable
> promise that Cooklist-style retailer integrations structurally cannot make.

---

## 5.7 PWA vs native: the honest tradeoff

| Capability | PWA (2026) | Verdict |
|---|---|---|
| Camera capture | ✅ `getUserMedia` / file input | Fine |
| Web Push, incl. iOS 16.4+ | ⚠️ iOS requires install-to-home-screen first, and **there is no install-prompt API** — observed custom-prompt install rates are 5–20% | **Existential, not a risk line** — though **less bad in Germany than the UK**: Germany is Android-dominant (iOS roughly 35–40% vs ~50% in the UK), so exposure is reduced, not removed. Still **~25–30% of the German user base would never receive the mechanic doc 4 calls "the product"** |
| **Notification action buttons** | ❌ **Safari Web Push does not support them.** Works on Chrome/Android | Doc 4 originally drew a two-button lock-screen notification **that cannot exist on half the target market**. Redesigned to a single action; two-button is now an Android/native enhancement |
| Offline | ✅ Service worker + IndexedDB | Fine |
| Voice input | ⚠️ Web Speech patchy on iOS | Fall back to audio upload + server transcription |
| Background sync | ⚠️ Limited on iOS | Server-side scheduling instead — we already do this |
| Install friction | ❌ Meaningful drop-off vs App Store | Mitigate with a well-timed install prompt *after* the first value moment |

> ⭐ **A second, independent reason to build the shell** ([doc 12 §12.2a](12-technical-research-capture.md#2a-auto-capture-of-receipts--adopt-native-shell-v2)):
> **automatic receipt capture** — camera opens, edges detected, shutter fires itself — is mature
> and free natively (**ML Kit Document Scanner** on Android, **VisionKit** on iOS) and saves 3–5 s
> of a 30-second budget. It is **not** available on the web: the Shape Detection API is broken on
> iOS 18 and never reached Baseline, and an OpenCV.js fallback is multi-MB WASM at ~10–15 fps with
> a real battery cost. **Ship plain photo capture on web in v1; add auto-capture in the shell in
> v2. Do not build the OpenCV.js version.**

**Decision: PWA for v1**, with three corrections from review:

1. **An email fallback alert channel ships in v1.** One day of work, it works everywhere, and a
   17:00 email is a legitimate delivery mechanism for this use case. Previously there was **no
   fallback at all** if push was unavailable.
2. **The native decision moves before the retention gate, not after.** Measuring G2 on a
   population where a large minority never received push makes the gate uninterpretable — we
   would either kill a working product for a platform reason, or pass on Android-skewed data and
   be surprised at launch. Ship the thin iOS shell *during* the beta, or stratify G2 explicitly by
   platform and push status.
3. **Auto-capture is a second, independent reason for the shell.** ML Kit Document Scanner
   (Android) and VisionKit (iOS) both provide automatic edge detection and shutter — removing 3–5
   seconds from every capture. On the web, the **Shape Detection API is broken on iOS 18** and was
   never Baseline, and an OpenCV.js fallback is a multi-MB WASM payload at ~10–15 fps with a
   documented battery cost. **Ship plain photo capture on the web in v1; add auto-capture in the
   native shell in v2. Do not build the OpenCV.js version.** (`BarcodeDetector` is the exception —
   better supported, and we need it for the TSE QR.)
4. **The native shell is 2–3 engineer-months, not one** — shell + APNs + App Store review for a
   food app + privacy nutrition labels + a second release train.

---

## 5.8 Unit cost model — corrected twice

> ⚠️ **Correction 1 (engineering review).** The original model priced OCR at list-price rates we
> would not get, and — the real error — computed **cost per household** while revenue arrives
> **per paying household**. At 3% conversion, 97% of users are pure COGS.
> ⚠️ **Correction 2 ([doc 12](12-technical-research-capture.md)).** Replacing the OCR vendor with
> direct VLM extraction cuts parsing cost **~40×**, which changes the answer materially.

**Cost per receipt:** ~**$0.0008** on a Gemini-Flash-class model (≈1,550 image tokens in, ~900 JSON
tokens out); ~$0.0024 on a GPT-5-Mini tier; ~$0.0078 on a Claude-Haiku tier. With a ~15% second
pass on a stronger model, **blended ≈ $0.0015–0.002** — against **$0.04–0.08** for negotiated
commercial OCR.

| Per paying household / month | Before (OCR vendor) | **After (VLM-first)** |
|---|---|---|
| Receipt parsing | €0.28 | **€0.02** |
| LLM normalisation | €0.02 | *(included above)* |
| Infra, storage, push (EU region) | €0.05 | €0.05 |
| **Direct COGS** | €0.35 | **€0.07** |
| Allocated free-tier cost | €0.40 | **€0.04** |
| **Fully loaded COGS** | **€0.75** | **€0.11** |
| Net ARPU | €2.19 | €2.19 |
| **Gross margin** | 66% | **95%** |

**Gross margin at 10k households and 3% conversion** — the table that was previously negative in
its worst row:

| Scenario | Monthly revenue | Monthly COGS | Gross margin |
|---|---|---|---|
| Original assumptions ($0.01/receipt list price) | €2,190 | ~€780 | 64% |
| Realistic **OCR vendor** ($0.06/receipt) | €2,190 | ~€1,450 | 34% |
| Realistic OCR vendor, free users at the cap | €2,190 | ~€2,800 | **negative** |
| **VLM-first** | **€2,190** | **~€110** | **95%** |

**The free-tier abuse risk shrinks with it.** A free active household now costs ~**€0.006/month**
to serve rather than ~€0.04. Rate limiting and device-bound identity (§5.6) are **still required** —
but **the blast radius is 40× smaller**, which is what makes an organic-only growth strategy
survivable.

⚠️ **Honest caveat on break-even.** Cheaper parsing barely moves the *blended* break-even
(96,500 → **~91,800** active households), because in the blended model the hand-off commission
dominates contribution. **The real gain is risk reduction, not volume.**

**Free tier design:** unlimited items (never cap items — that's the competitors' mistake and it
directly causes drift). The **2 receipt scans/month** cap was set when scans were the expensive
thing; at €0.0008 a scan **that constraint is now nearly free to relax**, and
[§6.2](06-business-plan-roadmap.md#62-business-model--redrawn-after-review-re-priced-for-germany)
should be revisited on packaging grounds rather than cost grounds.

## 5.9 Alternative stack

If the team is TypeScript-strongest: Next.js (App Router) + Postgres (Neon/Supabase) +
Inngest/Trigger.dev for jobs + the same external services. **Do not pick a stack for novelty.
The receipt pipeline is the hard part; everything else is CRUD.**

## 5.10 Non-functional targets

| Metric | Target |
|---|---|
| LCP, mid-tier Android, 4G | < 2.0 s |
| Today screen interactive from icon tap | < 1.0 s (cached shell) |
| Receipt parse p50 / p95 | < 8 s / < 20 s ⚠️ *widened: a VLM takes 3–10 s on a long receipt vs 1–2 s for OCR. Upload-and-dismiss with async completion is mandatory, not optional* |
| **Model-version eval re-run** | ⚠️ *New standing ops cost.* The full 200-receipt eval re-runs on **every** model version change, with temperature 0, a pinned version and the prompt hash recorded. The OCR vendor used to absorb this for us |
| Uptime | 99.5% (v1), 99.9% (post-PMF) |
| Timezone-sharded decay passes (24+ per day), 100k households | < 10 min per shard |
| **Model-version eval re-run** | On every VLM version change, the full 200-receipt eval must pass before rollout. ⚠️ *A new standing ops cost — the OCR vendor used to absorb this* |
| **Alert-volume SLO** | alerts per 1,000 households per week must stay inside a band — outside it, page. ⚠️ *Added after review: the failure mode of this system is silence, which is also the designed happy path. If the decay pass dies or push subscriptions expire en masse, the product is invisibly dead and no user will report it.* A synthetic canary household exercises the full loop hourly |
| Push delivery p95 | < 60 s of scheduled time |
