# 9. Investor Pack — The Numbers, With Assumptions Written Down

> **Launch market: Berlin → Germany → DACH.** Rationale and canonical market figures in
> [doc 11](11-germany-berlin-market.md). All figures in **€**. German VAT **19%**.
>
> **Status: pre-revenue. Nothing has been sold. No product exists.** Every figure below is a
> model, and every model states its assumption. Where a number is unknowable without the
> founder, it is marked **[FOUNDER TO COMPLETE]** rather than invented.

---

## 9.1 The customer and the problem

### Who specifically — not "everyone"

| | **Primary: the "Dienstag-Chaos" household** | Secondary: the Berlin single |
|---|---|---|
| Who | 2 working adults + 1–2 children, 30–45 | 25–38, single-person household |
| Where they actually are | Marzahn-Hellersdorf, Spandau, Reinickendorf, Treptow-Köpenick, Brandenburg commuter belt | Friedrichshain-Kreuzberg, Neukölln, Mitte |
| Shops | One big weekly shop (Edeka/REWE/Kaufland) + discounter top-ups | 2–3 small shops/week, plus Flink/Knuspr |
| Grocery spend | €130–190/week | €50–80/week |
| Waste behaviour | **High and unacknowledged** — fresh produce, Brötchen, leftovers | Low–moderate, but *aware* and motivated |
| Why they waste | Time pressure, plans change, discounter multipacks, no visibility into the back of the fridge | Buys for a plan they abandon |
| **Strategic note** | **Needs it most, adopts least.** The unclaimed position ([§8.4 Gap 2](08-why-the-category-underperforms.md)) | **Adopts most, needs least.** Berlin is **50% single-person households** — this segment will find us first and flatter every metric |

> ⚠️ **Berlin's demographics work against our primary customer.** Berlin averages **1.76 persons
> per household** against **2.01** nationally, and Friedrichshain-Kreuzberg — where a Berlin
> startup instinctively recruits — is **59.2% single-person**, the least representative district in
> the country for this product. Recruiting there would reproduce the category's canonical
> selection-bias failure at speed, while feeling like traction.
> **Phase 0 recruits in the outer Bezirke, targeting ≥16 of 25 households with children.**

**German waste composition validates the product design exactly:** **35% of avoidable household
waste is fresh fruit and vegetables, 13% is bread and bakery** (GfK for BMEL). Nearly half the
problem sits in two categories with **no barcode, no printed date and a shelf life of days** —
which is precisely why v1 is receipt-first and barcode-free.

### What they do today instead — the real competitor

| Current behaviour | Cost to them | Why it wins today |
|---|---|---|
| **Opening the fridge door** | 3 seconds | Free, instant, 100% accurate. **This is the real competitor** |
| A photo of the fridge before shopping | 5 seconds | Zero setup, offline, no app |
| A note on the fridge / a WhatsApp message to the partner | ~30 s/week | Already installed, already a habit |
| **foodsharing.de / Too Good To Go** | Free | Solves a *different* job (surplus), but **anchors the price of "food waste tools" at zero** in German minds |
| Memory | 0 | Fails silently — and the failure is invisible, which is why it persists |
| Nothing at all | 0 | The modal answer |

**Nobody is currently paying anything**, and in Germany two of the best-known options are free and
civic. There is no budget line to capture and no incumbent to displace — which is worse, not
better, than facing a paying market.

### Would they switch, and what would they pay?
**Unknown, and that is the honest answer.** Stated willingness-to-pay in this category is
worthless ([§8.2](08-why-the-category-underperforms.md), the intention–action gap). The evidence
we will accept:
1. **Capture compliance ≥60% at week 6** in the Berlin concierge test — revealed behaviour
2. **A pre-sale: 100 × €19 lifetime founder licences, cash taken**, to a cold German audience

---

## 9.2 The market

### Size and growth, with sources

| Layer | Figure | Source | Confidence |
|---|---|---|---|
| German grocery market | **€282.5bn** (2025) | Trade estimates / Statista | High |
| Retail concentration | Edeka €84.7bn · REWE Group €70.6bn · Schwarz (Lidl+Kaufland) €61.3bn · Aldi €36.9bn. **Edeka + REWE = 46.8%** | Grocery Trade News 2025 | High |
| **German online grocery share** | **~2.4% of retail volume** | Statista / ECDB | High — **and strategically critical** |
| German quick commerce | → **$6.42bn by 2029**; Flink, Knuspr, REWE, Amazon ≈ 70% share | Databook 2026 | Medium |
| German private households | **41.13m**, avg 2.01 persons, 42.1% single | **Destatis Mikrozensus 2025** | High |
| Berlin households | **~2.23m** total; 977k single-person (50%); avg 1.76 | Amt für Statistik Berlin-Brandenburg | High |
| German food waste | **10.9m t (2023)** across the chain; **58% from households**; **~79 kg/person/yr** | BMLEH / Destatis | High |
| Avoidable household waste mix | **35% fresh produce, 13% bakery, 12% drinks, 9% dairy** | GfK for BMEL | High |
| "Food waste app market" | $1.2bn (2024) → $5.7–6.6bn (2035), ~16.8% CAGR | Introspective MR | ⚠️ **Low — treat as marketing.** Bundles B2B kitchen analytics and marketplaces with consumer apps |

**Is the market growing, flat, or being disrupted?**
- The *problem* is flat: German household waste has not fallen materially despite a national
  strategy and the BMLEH's "Zu gut für die Tonne!" campaign.
- *B2B* waste analytics is genuinely growing and genuinely funded.
- *Consumer prevention* is flat and repeatedly re-attempted — a graveyard, not a growth curve.
- It **is** being disrupted, but by a general-purpose technology: post-LLM receipt parsing removed
  the constraint that killed Kitche. That window is open to everyone simultaneously.

### Top competitors

*German-market view; the full international teardown is in [§1.2](01-market-competitive-research.md)
and the German-specific landscape in [§11.4](11-germany-berlin-market.md#114-the-german-competitive-landscape).*

| Competitor | Positioning | Pricing | Status | Weakness we exploit |
|---|---|---|---|---|
| **Too Good To Go** | Surplus marketplace | Free to user; ~€1.79/bag + merchant sub | €610m revenue, 120m users; very strong in DE | Different job — but **owns the "Lebensmittelrettung" association**, a positioning constraint |
| **foodsharing.de** | Volunteer peer-to-peer redistribution | **Free** | Large, culturally significant in Berlin | Free and civic — **anchors expectations at zero** |
| **SirPlus** (Berlin) | Rescued-food retail + online | Retail margins | **Insolvency; returned online 2026** | **The local cautionary tale.** Will be raised in every Berlin investor meeting — address it first |
| **"Zu gut für die Tonne!"** (BMLEH) | Government app: tips, recipes, leftovers calculator | Free | Official, well-known | **A free state information product** — proof that information-only has no commercial space here |
| **Motatos** | Discount rescued-food e-commerce | Retail | Swedish, in DE since 2020 | Redistribution, not prevention |
| **NoWaste.ai** | AI receipt-to-pantry | Free (50 items), $4.99–9.99/mo | Active internationally | Item caps cause drift; **no German retailer templates**; no consumption model |
| **Cooklist** | Loyalty-account sync | Free + sub | US-centric | Requires loyalty accounts; German loyalty penetration is low and fragmented |
| **Fango** | Receipt-only, 34 countries | €2.99/mo | Active | **Closest analogue to our v1 — our primary disconfirmation.** Weak German localisation |
| **KptnCook, Bring!** | Recipes / shopping lists, DACH-native | Free + premium | Large German installed bases | Adjacent — **plausible partners or acquirers**, not competitors |

**Structural read:** in Germany as elsewhere, the money sits in B2B and marketplaces.
**The prevention slot is empty — and in Germany the price of adjacent tools has been anchored at
zero by a volunteer network and a government app.** That is either the opportunity or the verdict;
[§8.3](08-why-the-category-underperforms.md#83-the-comparison-that-explains-everything) argues it
is closer to the verdict than founders like.

### Substitutes and indirect alternatives
Meal kits (HelloFresh — Berlin-headquartered, and the most under-rated substitute: it solves the
same job by removing the choice, with a business model that works); REWE/Picnic "usual order"
repeat-buy; Flink and Knuspr making top-up shops trivial; smart fridges; freezing; a paper list;
foodsharing; shopping more often — which German shoppers already do.

---

## 9.3 How we reach customers, and what it costs

> Benchmarks: median freemium→paid **2–5%**; mobile freemium D35 download-to-paid **2.1%**;
> hard-paywall 10.1%; average subscription **CAC $72**; apps at $5–15/mo have LTV $40–120
> supporting CAC $15–40 *(RevenueCat 2026; Business of Apps)*. **We price below that band, so our
> supportable CAC is proportionally lower.**

| Channel | How it works here | Cost/install | Install→paid | **CAC per paying customer** | Verdict |
|---|---|---|---|---|---|
| **Referral / household invite** | Inviting a partner is a product action, not a campaign | €0.35 | 6% | **~€6** | ✅ **Best channel by an order of magnitude.** Design for it |
| **Assistant-native (MCP)** | Zero install friction | €0.25 | 2% | **~€12** | ✅ Cheap experiment, unproven volume |
| **Partnerships** — Berliner Bezirke, BMLEH "Zu gut für die Tonne!", Verbraucherzentrale, housing associations | German public bodies actively fund waste-reduction comms, and the vocabulary already exists | €0.55 | 3.5% | **~€16** | ✅ Credible and cheap; slow to land. **Stronger in Germany than the UK** |
| **Short-form video** — the Bon-scan demo | The capture moment is satisfying to watch; the Bonpflicht grievance is a native hook | €0.70 | 2.5% | **~€28** | ✅ Worth a real attempt |
| **Content / SEO** — *"Wie lange hält Brokkoli im Kühlschrank?"*, MHD vs Verbrauchsdatum | Maps onto our data asset; high intent | €0.90 | 3% | **~€30** | ⚠️ Viable but **AI-Overview-threatened**. German-language SEO is less contested than English, which partly offsets it |
| **Paid social** | — | €2.80 | 2% | **~€140** | ❌ **Structurally unviable at our price point** |
| **App store search** | — | €1.30 | 3% | **~€43** | ❌ Above LTV |

**Realistic blended CAC with paid excluded: ~€20 per paying customer.**
**With any meaningful paid mix: €30+, which is above subscription-only LTV.** Stated plainly:
*this business cannot buy its customers.* It is organic-or-nothing — which caps growth rate, and
is itself an argument against a large equity raise.

---

## 9.4 Operations and cost

| Area | Detail |
|---|---|
| **"Suppliers"** | ⚠️ *Changed in [doc 12](12-technical-research-capture.md): the commercial OCR vendor is removed — a vision LLM reads the receipt end-to-end at ~40× lower cost.* Vision-model provider (EU residency required), EU-region cloud host, push infrastructure, **Open Food Facts** (⚠️ **ODbL — share-alike may attach to a derived database; legal opinion is a Phase 0 blocker**), German shelf-life sources (BMLEH, Verbraucherzentrale) |
| **Lead times / MOQs** | No physical goods. The real lead times are regulatory and grant-related: **EXIST / Berlin Startup Stipendium applications take ~6–10 weeks**; a **DSGVO DPIA must complete before beta**; Gmail restricted-scope CASA review ($3k–15k, 4–12 weeks) is **avoided entirely** by shipping forward-to-address only |
| **Cost per unit (direct)** | Per paying household/month: OCR ~€0.28 (5 receipts @ ~$0.06 negotiated), LLM residual €0.02, infra/storage/push €0.05 = **€0.35 direct**. Plus **€0.40 allocated free-tier cost** = **€0.75 fully loaded** |
| **What breaks at 10×** | (1) **OCR cost scales with free users** — the only true variable cost, incurred on non-payers. (2) **Support**: human-in-loop review for the first 1,000 users is up to 5,000 receipts/month with nobody assigned. (3) **Retailer template drift** — Edeka is a federation of independent retailers with *non-uniform receipt formats*, which is a harder parsing problem than REWE or the discounters. (4) Timezone-sharded decay passes. (5) **Silence is our happy path and also our outage signature** |
| **Concentration risk** | Single OCR vendor = pricing and terms risk. **Dual-source from day 1** |

---

## 9.5 Legal and risk

| Area | Position |
|---|---|
| **Licences / permits** | None required. Not a regulated activity. Company form: **UG (haftungsbeschränkt)** initially, converting to **GmbH** — investors will expect a GmbH before a priced round |
| **Data protection** | **DSGVO + BDSG.** Receipts are high-risk personal data (reveal health, religion, pregnancy, addiction, income). **DPIA required *before* processing** — in Phase 0. **German consumers are the most privacy-conscious in Europe**, so consent flows must be genuinely minimal, in German, and revocable. EU-region hosting; US OCR/LLM transfer needs **SCCs + transfer impact assessment** — or an EU-resident OCR vendor, which is worth paying for |
| **Food safety** | ⚠️ **The live liability.** **Mindesthaltbarkeitsdatum (MHD, quality) vs Verbrauchsdatum (safety)** is the legally-loaded distinction. Verbrauchsdatum is **never** extended; high-risk categories hard-clamp; never the word "sicher". Explicit ToS disclaimer; **Produkthaftpflicht from day 1** |
| **Consumer law** | Fernabsatzrecht, 14-day Widerrufsrecht, and Germany's **Kündigungsbutton** requirement — a compliant one-click cancel for online subscriptions is **mandatory**, and annual-first pricing raises the stakes. Get this right before the paywall goes live |
| **IP — ours** | **DPMA trademark search + registration** for the name **[not yet done]**. No patents; none defensible. The defensible asset is the **learned German retailer dictionary and household priors** — trade secret and contract, not patent |
| **IP — others'** | ⚠️ **Open Food Facts is ODbL.** Retailer receipt formats are not IP-protected; retailer marks must not imply endorsement |
| **Advertising claims** | **UWG** — cannot claim a % waste reduction without substantiation, and German competition law is enforced by *Abmahnung* from competitors and Wettbewerbszentrale, not just a regulator. **Nobody in this category has substantiated an efficacy claim** ([§8.4 Gap 4](08-why-the-category-underperforms.md)) |
| **Insurance** | Berufshaftpflicht + Produkthaftpflicht + Cyber. ~€4–6k/yr |
| **Employment** | Standard; ensure IP assignment in every contractor agreement (German law does not assign contractor IP by default) |

---

## 9.6 Unit economics

*Per paying household unless stated. Germany. VAT 19%. Assumptions in italics.*

### Price and net revenue
| | Annual (target: 65% of mix) | Monthly (35%) |
|---|---|---|
| List price (VAT inclusive) | **€29.00/yr** | **€3.49/mo** |
| Less German VAT @19% | €24.37 | €2.93 |
| Less payment fees *(PayPal ~2.49%+€0.35 and SEPA Lastschrift; **web checkout primary** — see below)* | **€23.40** | **€2.63/mo** |
| Net revenue per month | €1.95 | €2.63 |
| **Blended net ARPU** | **€2.19 / month** | |

> **Why web checkout is primary, and why that matters to the margin.** German card penetration is
> the lowest of any major Western economy (**~11%** of online purchases); PayPal is ~28% and SEPA
> Direct Debit ~17%. App-store IAP is card-centric and would underperform badly here.
> Shipping **PayPal + SEPA on the web** is therefore both a conversion necessity **and** a margin
> advantage — it avoids the 15–30% store cut. This is a genuine German-market benefit.

### Cost per unit (direct only)
| Item | €/paying household/month | Assumption |
|---|---|---|
| **Receipt parsing (VLM-first)** | **0.02** | *5 receipts/mo. A vision model reads the receipt end-to-end for **~$0.0008–0.002**, against $0.04–0.08 for negotiated OCR — see [doc 12](12-technical-research-capture.md). Includes a 15% second pass on a stronger model* |
| Infra, storage, push (EU region) | 0.05 | |
| **Direct COGS** | **0.07** | |
| Allocated free-tier cost | 0.04 | *~32 free users per payer at 3% conversion; ~20% remain monthly-active; 2 scans/mo cap. **A free active household now costs ~€0.006/month*** |
| **Fully loaded COGS** | **0.11** | |

### Gross margin
| | €/month | % |
|---|---|---|
| Net ARPU | 2.19 | 100% |
| Fully loaded COGS | 0.11 | 5% |
| **Gross profit** | **€2.08** | **95%** |

⚠️ **This number moved twice, in opposite directions, and both moves matter.**
The original ">93%" was wrong for the right reason the reviewer identified — it counted cost per
*household* while revenue arrives per *paying* household, which gave a true figure of **66%**.
Then [doc 12](12-technical-research-capture.md) removed the OCR vendor: a vision LLM reads a
receipt for ~$0.0015 instead of ~$0.06, and the honest number becomes **95%**.
**At launch, with an empty German dictionary, expect ~85%** — improving as the dictionary fills.
The bootstrap problem that made costs peak when cash is scarcest is now small rather than severe.

### LTV, CAC and the ratio — the number that decides everything
*Churn: 8%/month on monthly plans (benchmark average 5.3%; top performers <3%; we assume worse
than average because engagement is deliberately low). Annual renewal 50%. Blended lifetime 20 months.*

| | Subscription only | **With Berlin quick-commerce hand-off** |
|---|---|---|
| Gross profit / month | €2.08 | €2.08 + **€0.99** = **€3.07** |
| **LTV (gross profit)** | **€42** | **€61** |
| Blended CAC (organic-only) | €20 | €20 |
| **LTV / CAC** | **2.1×** ⚠️ | **3.1× ✅** |
| CAC payback | 10 months | 7 months |

> **This is the first version of the model that clears the 3× LTV/CAC threshold** — and it does so
> only *with* the hand-off. On subscription alone it is 2.1×: survivable, not fundable.
>
> **The single most important structural finding still stands:**
> the grocery basket hand-off is **not a "second revenue leg for month 12" — it is the model.**
> The grocery basket hand-off is **not a "second revenue leg for month 12" — it is the model.**
>
> *Hand-off assumption: 45% of paying households complete one referred basket per month at €2.20
> average commission (5% of a ~€44 basket, against a 2–9%-of-cart benchmark). **This is the most
> sensitivity-critical assumption in the entire plan**, and it is why the launch city is Berlin:
> Germany's national online-grocery share is only ~2.4%, but Berlin is Europe's most competitive
> online-grocery city — Flink, Picnic, REWE, Knuspr, Flaschenpost, Amazon.*
>
> ⚠️ **And it is why Germany-wide rollout dilutes the model.** Outside the big cities there is
> often nowhere to hand the basket to. National expansion improves subscription volume and
> *weakens* per-user economics. That trade-off must be modelled, not discovered.

**It also flips the free tier.** A free active household costs ~€0.04/month and, at a 15% hand-off
rate, contributes ~€0.33/month gross profit. **Free users become contributors rather than a
subsidised cost** — which is what makes an organic-only, low-ARPU consumer product survivable.

### Repeat / churn
| Metric | Assumption | Benchmark |
|---|---|---|
| Monthly churn (monthly plans) | 8% | 5.3% avg; 6.7% streaming; <3% top decile |
| Annual renewal | 50% | |
| Free→paid conversion | **3%** | 2.1% freemium D35; 2–5% median. ⚠️ *Our earlier 5–6% target was above benchmark and has been corrected* |

---

## 9.7 Trading history

**Pre-revenue. Stated plainly, as it should be.**

| Year | Revenue | Profit / (loss) |
|---|---|---|
| Year before last | €0 | €0 |
| Last year | €0 | €0 |
| This year to date | €0 | **[FOUNDER TO COMPLETE — costs incurred to date, if any]** |

- No product built. No customer has paid anything. No pre-orders taken. No company formed yet.
- Assets to date: this research corpus and two independent senior engineering reviews of it.
- **[FOUNDER TO COMPLETE]** — founder capital invested to date and its source.

---

## 9.8 Forecast, cash and break-even

### Two honest paths

#### Path A — Lean (recommended)
Berlin beachhead, grant-funded founders, organic-only growth, hand-off revenue from month 10.

| | Y1 (to Sep 2027) | Y2 | Y3 |
|---|---|---|---|
| Installs (cumulative) | 35,000 | 170,000 | 450,000 |
| Monthly active households | 12,000 | 62,000 | 165,000 |
| Paying households | 600 | 3,000 | 9,000 |
| Subscription revenue | €14k | €78k | €234k |
| Hand-off commission | €24k | €164k | €436k |
| **Total revenue** | **€38k** | **€242k** | **€670k** |
| Gross profit | €32k (84%) | €225k (93%) | €630k (94%) |
| Operating costs | €395k | €540k | €640k |
| **Profit / (loss)** | **(€363k)** | **(€315k)** | **(€10k)** |
| Cumulative | (€363k) | (€678k) | (€688k) |
| *of which non-dilutive grant-funded* | *€110k* | *—* | *—* |

**Y4 +€454k · Y5 +€1.02m. Break-even ≈ month 36** *(was month 40 before the VLM cost collapse)*.
**Total capital: ~€850k–1.0m, of which ~€110k non-dilutive.**

#### Path B — Venture
Larger team, faster build, DACH in year 2, UK in year 3.

| | Y1 | Y2 | Y3 |
|---|---|---|---|
| Installs (cumulative) | 55,000 | 400,000 | 1,250,000 |
| Paying households | 1,000 | 7,200 | 25,000 |
| **Total revenue** | **€58k** | **€520k** | **€1.78m** |
| Operating costs | €760k | €1.40m | €2.05m |
| **Profit / (loss)** | **(€716k)** | **(€1.06m)** | **(€600k)** |

**Break-even ≈ month 38. Total capital ~€2.9m.** Requires the hand-off assumption to hold *and*
successful DACH entry. **Higher risk of the year-three B2B pivot** flagged in §6.6.

### Break-even analysis
*Fixed costs, lean team of 5 FTE in Berlin: **~€36,000/month.***

| Model | Contribution per unit | **Break-even volume** | As % of German SAM (2.05m installs) |
|---|---|---|---|
| Subscription only | €2.08 / paying household / mo | **17,300 payers ≈ 577k installs** | **28%** ⚠️ |
| **With hand-off, base** | ~€0.392 / *active* household / mo | **~91,800 actives ≈ 278k installs** | **14%** ⚠️ achievable |
| With hand-off, best case | ~€0.65 / active household | **~55,400 actives** | **8%** ✅ |

⚠️ **Note what cheaper parsing did and did not fix.** Subscription-only break-even improved from
41% to 28% of SAM — real, but still not a viable standalone path. The *blended* break-even barely
moved (96,500 → 91,800 actives) because **the hand-off commission dominates contribution**.
The gain from VLM-first is risk reduction, not volume.

> **Berlin alone cannot pay for the company.** Berlin's entire SAM is ~97,000 installs
> ([§11.6](11-germany-berlin-market.md#116-market-sizing-germany-bottom-up)) — **below the
> break-even volume on every model.** Berlin proves the loop; Germany pays for it. Any plan that
> treats Berlin as the market rather than the proving ground is wrong.

### Cash flow (next 18 months, Path A, €k)

| Month | 1–3 | 4–6 | 7–9 | 10–12 | 13–15 | 16–18 |
|---|---|---|---|---|---|---|
| Opening cash | 360 | 297 | 214 | 121 | 452 | 356 |
| Revenue in | 0 | 0 | 2 | 8 | 22 | 48 |
| Costs out | (63) | (83) | (95) | (107) | (118) | (128) |
| Funding in (seed) | — | — | — | **430** | — | — |
| **Closing cash** | **297** | **214** | **121** | **452** | **356** | **276** |
| Runway at that burn | 14 mo | 8 mo | **4 mo** ⚠️ | 13 mo | 9 mo | 6 mo |

**Burn: ~€21k/month in Phase 0, rising to ~€43k/month post-team.**
**The €360k pre-seed gives ~11 months. The seed must close by month 10 → start raising month 6.**

---

## 9.9 Market sizing (TAM / SAM / SOM)

Built bottom-up: **customers × price × frequency.** No "1% of a €280bn market" anywhere.

```
TAM — German households buying fresh food
  41.13m private households                    (Destatis Mikrozensus 2025)
  × 92% smartphone + weekly shop                = 37.8m
  × 80% buy fresh food regularly                = 30.3m
  TAM value @ €29/yr                            = €878m/yr theoretical

SAM — households we can serve and reach
  30.3m
  × 45% who report throwing food away often     = 13.6m   problem-aware
  × 15% who would install a food app            =  2.05m  ⚠️ STATED INTENT
  Subscription @ 3% conversion × €29            = €1.78m/yr
  Hand-off: 15% of ~680k actives × €2.20 × 12   = €2.69m/yr
  SAM total                                     ≈ €4.5m/yr

BERLIN (beachhead only)
  1.95m private households → ~97,000 installs   ≈ €215k/yr at full saturation
  BELOW break-even on every model

SOM — realistically winnable in 3 years
  Path A: 450k installs = 22% of German SAM     ≈ €670k/yr
  Path B (DACH):  1.25m installs                ≈ €1.78m/yr
```

> ⚠️ **Two honest corrections.** **(1)** The 15% "would install" is *stated intent*, and
> [§8.2](08-why-the-category-underperforms.md) shows stated intent overstates revealed preference
> by roughly an order of magnitude in this category — the defensible SAM may be **3–5× smaller**.
> **(2)** Multiplying two survey percentages compounds that error. **Treat SAM as an upper bound,
> not a forecast.** The concierge test and a pre-sale exist to replace this number with a real one.

Germany's SAM is ~46% larger than the UK equivalent on household count (41.1m vs 28.4m), and the
Bonpflicht makes capture materially easier — but the honest caveats are identical.

---

## 9.10 The deal

### The ask: **€360,000, of which only €250,000 is dilutive**

Deliberately not the £750k–1m originally proposed. Both senior reviewers argued that raising
that much against a €2–3m ARR ceiling structurally mismatches the outcome and forces a year-three
pivot into a different company. **Berlin's funding infrastructure lets us do better than a
straight equity round.**

| Source | Amount | Dilutive? |
|---|---|---|
| **EXIST-Gründerstipendium** *or* **Berlin Startup Stipendium** (2 founders × 12 months) | **~€110k** | ❌ **Non-dilutive** |
| **IBB Ventures B# Pre-Seed** (convertible; the fund does €100k–400k tickets) | **€250k** | Deferred (convertible) |
| **Total** | **€360k** | Only €250k dilutive |

**Use of funds — the full table is in [§11.7](11-germany-berlin-market.md#117-the-revised-ask).**
Headline lines: **€18k concierge test** (25 Berlin family households, humans doing everything the
software would), €78k senior engineer for 9 months, €22k German receipt corpus and labelling,
€20k German shelf-life curation, €18k legal (DSGVO DPIA, ODbL opinion, DPMA mark,
Kündigungsbutton), €12k PayPal/SEPA integration.

### Valuation and justification

**Instrument: a convertible with a cap around €2.5m and a 20% discount.**

| | |
|---|---|
| Raising (dilutive portion) | €250,000 |
| Instrument | Convertible note / SAFE-equivalent (Wandeldarlehen) |
| Cap | ~€2.5m |
| Discount | 20% |

**Why a convertible rather than a priced round:** [§10.8](10-frameworks-and-financials.md#108-discounted-cash-flow)
shows the DCF produces an NPV of roughly **€650k** against a €2.5m cap. **The cash flows do not
support the cap** — the valuation would rest on comparables and option value, which is normal at
pre-seed but is a weak argument to have *before* the concierge test. A convertible defers the
argument until there is evidence to have it with. IBB's B# fund uses exactly this instrument.

**Against us, stated plainly:** no product, no revenue, no traction, no pre-orders, and a category
with a 15-year record of failure — including **SirPlus's insolvency, in Berlin, with a famous
founder and real stores.** A disciplined investor should discount for that, and a founder who
argues otherwise is not reading their own market research.

### Founder investment
**[FOUNDER TO COMPLETE]** — amount invested to date and its source. Investors will ask, and the
honest answer, whatever it is, beats a vague one.

### Milestones this round buys
1. **Concierge test reports (month 3) — the go/no-go**
2. Receipt parser at a *defined* F1 metric across **10 German chains**, on a household-photographed
   corpus (month 5)
3. Consumption model validated against the concierge households' real data (month 6)
4. DSGVO DPIA complete, ODbL position resolved, DPMA mark filed (month 4)
5. **A pre-sale: 100 paid €19 lifetime founder licences** (month 7) — the first real demand evidence

**If milestone 1 fails, we return the remaining capital or re-scope openly.** Written into the
plan on purpose.
