# 0. Executive Summary

**Product:** Crisper — a responsive PWA that tells a household what food it has and what is about
to die, capturing inventory from grocery receipts with near-zero manual input.

**Launch market: Berlin → Germany → DACH.** Rationale: [doc 11](11-germany-berlin-market.md).

**Visual companion:** [Interactive product brief](https://claude.ai/code/artifact/bcd6a143-4d45-4464-af49-7a5f7e19a9e3)
— screens, decay model, market research, unit economics and the ask.

---

## The finding that should shape everything

This is not an unexplored idea. It is a **fifteen-year graveyard**, and every headstone reads the
same:

> The app required the user to keep a list true. Nobody can. The list drifts, the user stops
> trusting it, and they churn in week three.

Fridgely (barcode-only, notorious false expiries), Pantry Check (great scanner, hand-typed dates),
CozZo (every feature, junk item names, crashes), Kitche (right thesis, pre-LLM tech — acquired
2025), Grocy (excellent, requires a server). Even **Samsung**, with a camera inside the fridge, a
decade and unlimited budget, recognises 37 fresh items and files the rest as *"unknown item."*
In Germany specifically, **SirPlus** — a famous Berlin food-waste brand with real stores and a
celebrated founder — went through insolvency.

The only breakout in food waste — **Too Good To Go, €610m revenue, 120m users** — isn't an
inventory app at all. Zero setup, an immediate concrete reward, a transaction, and **no state the
user must maintain**.

## Why the category underperforms — and there is real research on this

EU Horizon 2020 (LOWINFOOD) trialled a pantry app in 50 households across three countries. A 2023
systematic review covered every food-waste platform it could find. A 2025 review covered every
experimental waste-reduction intervention. Two findings dominate ([doc 8](08-why-the-category-underperforms.md)):

1. **People don't believe they have the problem.** WRAP's own research: *many people thought they
   didn't waste significant amounts of food.* You cannot sell a solution to a problem the buyer
   doesn't think they have — and every app in the graveyard opened with "reduce your food waste."
2. **Nobody has ever proved one works.** *"None of the studies investigated whether platforms
   succeeded or failed in contributing positively to environmental impacts."* The category has no
   credible efficacy claim, so nobody can advertise one.

**The comparison that explains it all:** the same technology — computerised waste tracking — cuts
waste **64% by mass** in commercial kitchens and nearly nothing in homes. In a commercial kitchen
waste is measured daily, owned by a chef with a P&L, and using the tool *is the job*. At home it
is unmeasured, unowned, and extra work. **The category's success is real — it lives in B2B.**

## Why Germany, and why Berlin

Four reasons, one decisive:

1. ⭐ **The Belegausgabepflicht.** Since 1 January 2020, German law requires a receipt for *every*
   till transaction — regardless of amount, **even if the customer doesn't want one.** Our entire
   capture thesis rests on the user holding a receipt. In the UK, shoppers increasingly decline
   paper. **In Germany, the input to our product is placed in every shopper's hand by law,
   several times a week.** It is also widely resented as paper waste, which hands us a native
   hook: *"Wir machen den Bon endlich nützlich."*
2. **Ten receipt templates cover ~80% of German grocery spend** (Edeka, REWE, Lidl, Aldi Nord/Süd,
   Kaufland, Penny, Netto, dm, Rossmann). The UK needs ~7; the US needs hundreds.
3. **Berlin has non-dilutive founder funding** — EXIST-Gründerstipendium (€2,500/founder/month),
   Berlin Startup Stipendium, IBB Ventures B# Pre-Seed (€100k–400k).
4. **Berlin is Europe's most competitive online-grocery city** — Flink, Picnic, REWE, Knuspr,
   Flaschenpost, Amazon — and that is where the revenue model works. Germany's *national*
   online-grocery share is only ~2.4%.

**And German waste data validates the product design exactly:** the GfK study for the BMEL finds
**35% of avoidable household waste is fresh produce and 13% is bread and bakery** — 48% in two
categories with **no barcode, no printed date, and a shelf life of days.** That is why v1 is
receipt-first and barcode-free.

> ⚠️ **The honest counterweight: Berlin's demographics are wrong for our primary customer.**
> Berlin is **50% single-person households** (1.76 persons average vs 2.01 nationally); waste
> concentrates in families. Recruiting in Friedrichshain-Kreuzberg (59.2% single) would reproduce
> the category's canonical selection-bias failure while feeling like traction. **Phase 0 recruits
> in the outer Bezirke, ≥16 of 25 households with children. Berlin proves the loop; Germany pays
> for it** — Berlin's entire SAM is ~97,000 installs, below break-even on every model.

## The three bets

1. **Passive capture is finally good enough.** Post-LLM receipt parsing crosses the threshold that
   made this impossible in Kitche's era — and German law guarantees the receipt exists.
2. **An inventory allowed to be wrong retains better than one required to be right.** Items are
   hypotheses with confidence, not facts, and they **auto-retire** when we stop believing our own
   guess. The user is never asked to tidy up.
3. **One well-timed weekly notification is worth more than a whole inventory app.** RCT evidence:
   information alone changes nothing; moment-of-decision prompting cut avoidable waste ~30%.

**And bet 0, which we had not written down:** *people will keep capturing, and will act when
prompted.* Reviewers identified this as the real existential bet.

## What that means concretely

| | Legacy category | Crisper |
|---|---|---|
| Items are | facts the user maintains | hypotheses with a confidence score |
| Stale items | accumulate forever | **auto-retire silently** |
| Consumption | must be logged | **inferred from repurchase cadence** — free from receipts |
| Expiry | a precise (often wrong) date | a **window with an uncertainty band** |
| Wrong data | the user's fault | our model's fault, one tap to fix |
| Notifications | engagement lever | **capped at 3/week, default 1, server-enforced** |
| Weekly effort | ~5 min of typing per shop | **≤ 3 min total** |
| Language | "EXPIRED" / "abgelaufen" | *"Lohnt sich zu prüfen"* |

The database stores `window_start`/`window_end`, never `expires_on` — so it is structurally
impossible for the UI to render a precision we don't have. Architecture enforcing a product promise.

## What two independent senior reviewers changed

Neither would fund it as originally scoped. Full record: [doc 7](07-engineering-review.md).

1. **"Consumption is inferred" had no mechanism.** The engine modelled *spoilage*, so inference
   was a 130% timer — and composed with an 80–130% alert band, **the design fired alerts precisely
   when food is most likely already eaten.** Estimated stale-alert rate 40–55% against a ≤20%
   target. **Fix:** infer presence from repurchase cadence. Build it *before* the parser.
2. **We modelled the wrong error.** Auto-retirement handles ghosts. It does nothing about **missed
   captures** — the shop you never photographed. Honest compliance forecast: 70–80% of shops in
   week 1, **25–35% by week 8**. *"No UI fixes forgetting."* (Germany's Bonpflicht is the best
   available answer to this.)
3. **The cost model was wrong in the direction that kills the company.** Cost is per household,
   revenue per *paying* household — at 3% conversion, 97% of users are pure COGS. The claimed
   ">93% gross margin" holds under no assumption. **Real: 66%, and ~30% at launch.**
4. **Phase 0 asked the wrong question** — the fun engineering one, not the existential one.

Also corrected: three load-bearing charts were invented and are now labelled as such; the
load-bearing citation for the core thesis was three *competitor marketing blogs*; Safari Web Push
has no notification action buttons, so the notification we'd drawn couldn't exist for ~40% of
users; and the MVP was estimated at 15 weeks against a realistic 26–32.

## The economics that decide it

| | Subscription only | With Berlin quick-commerce hand-off |
|---|---|---|
| Gross profit / month | €2.08 | **€3.07** |
| LTV (gross profit) | €42 | **€61** |
| Blended CAC (organic-only) | €20 | €20 |
| **LTV / CAC** | **2.1×** ⚠️ | **3.1×** ✅ |

**Break-even against a €36k/month base:** subscription-only needs **~17,300 payers ≈ 28% of the
German SAM.** With the hand-off: **~91,800 active households ≈ 14%.**

> ⭐ **The margin has been corrected twice, and the second correction is the good one.** The
> original ">93%" was wrong for the right reason — it counted cost per household while revenue
> arrives per *paying* household — and the honest figure was **66%**. Then
> [doc 12](12-technical-research-capture.md) replaced the commercial OCR vendor with **direct
> vision-model extraction at ~$0.0008 per receipt against $0.04–0.08 — roughly 40× cheaper** —
> taking fully-loaded COGS from €0.75 to **€0.11** and margin to **95%**. This is the first version
> of the model that clears the 3× LTV/CAC threshold, and **it got there by cutting cost, not by
> assuming better user behaviour** — the only kind of improvement worth trusting in a plan with no
> primary evidence yet.
>
> **And the risk moved rather than vanished.** A vision model returns no per-field confidence, and
> a hallucinated line item is *worse* than an OCR error because it reads correctly. **German
> receipts hand that back three times over:** the printed **Summe** as an answer key, the
> legally-mandated **A (7%) / B (19%) VAT class** as a free per-line food classifier.
> ⚠️ *A third check — the TSE QR code — was proposed, checked, and dropped: it carries no amounts
> or VAT subtotals, only tamper-evidence for the tax office. It survives as free duplicate
> detection and an exact purchase timestamp.* **Two legally-guaranteed checks is still more than
> any other market offers, and Germany remains the best-instrumented receipt market in Europe.**

> **The grocery basket hand-off is not a "second revenue leg for month 12" — it is the model.**
> And **paid acquisition is impossible**: €140 CAC through paid social against a €29 LTV. This
> business is organic-or-nothing, which caps growth rate and is itself an argument against a
> large equity raise.

**Porter is blunt:** three of five forces at maximum — and buyer power is *worse* in Germany,
because foodsharing.de and a free BMLEH app have anchored the reference price at **zero**.
This is a structurally unattractive industry. It can still contain a good business, but only by
changing the game: move to where a transaction exists, and build the assets that compound.

## The plan

- **Phase 0 (8 wks, ~€18k, no product code):** a **human concierge test** — 25 high-waste Berlin
  households in the outer Bezirke, a WhatsApp group, humans parsing Bons and sending the Wednesday
  message. Measure **capture compliance week 1 vs week 6** and **rescue-on-prompt rate**. Software
  can only be worse than a human concierge, so this is the ceiling. Running alongside: the
  200-receipt German corpus, the parser spike, the **DSGVO DPIA**, the **ODbL legal opinion**, and
  the grant applications. **Gate 1.**
- **Phase 1 (15 wks):** consumption model first, then receipt capture, freshness engine (MHD vs
  Verbrauchsdatum), Today screen, notification budget, PayPal/SEPA checkout, iOS shell →
  400-household closed beta. **Gate 2 — W3 retention ≥35%, stratified by household size. Do not
  launch if this fails.**
- **Phase 2:** sharing, sweep, **quick-commerce hand-off**, savings artifact → Berlin launch with
  the paywall on, then Germany-wide. **Gate 3.**
- **Phase 3:** DACH (shared language, shared chains), then the UK — which needs a *different*
  capture strategy, because it has no Bonpflicht.

## The ask

**€360,000 — of which only €250,000 is dilutive.**

| Source | Amount | Dilutive? |
|---|---|---|
| EXIST-Gründerstipendium / Berlin Startup Stipendium | ~€110k | ❌ **No** |
| IBB Ventures B# Pre-Seed (convertible, cap ~€2.5m, 20% discount) | €250k | Deferred |

**Why a convertible:** the DCF produces an NPV of ~**€649k** against a €2.5m cap. **The cash flows
do not support the cap.** A convertible defers that argument until the concierge test has produced
evidence to have it with. Saying so is better than being caught by it.

## Kill criterion, written down while nobody is invested

> If week-12 household retention is below **12%** after two serious iterations of the core loop,
> the product does not work and we stop.

## The single biggest risk

Not competition, not technology. **People don't care enough for long enough** — and the sharper
version: **selection inverts the value.** Waste concentrates in large, chaotic, time-poor
households with children, who are least likely to install. The people who install are already
conscientious and waste least. *"Every app in the graveyard was used by the people who needed it
least."* Berlin, at 50% single-person households, makes this trap easier to fall into, not harder.

The live strategic alternative the concierge test is designed to surface: reframe the wedge from
**"what you have"** to **"what to cook tonight."** One reviewer predicts it will point there.
We test it rather than assume it either way.

**Bottom line: spend €18k and eight weeks on a human concierge before spending €700k on software.**
Three of doc 12's open questions — magnet-compatible fridge fronts, filmed unpacking, and what
actually happens in those 90 seconds — cost **nothing extra** because the concierge test is already
in those kitchens. *(A fourth, the TSE QR payload, has since been checked and answered: it is not
a checksum.)*
Trading history is €0 across all three years, no product, no customers, **no pre-orders, and zero
customer interviews conducted.** The cheapest thing left to do is 25 Berlin households and a
WhatsApp group — then taking €19 off a hundred strangers.
