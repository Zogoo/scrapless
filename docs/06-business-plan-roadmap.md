# 6. Business Plan & Roadmap

## 6.1 TAM, bottom-up (not top-down)

> **Launch market changed to Berlin → Germany → DACH.** Rationale and canonical figures:
> [doc 11](11-germany-berlin-market.md). Full sizing: [§9.9](09-investor-pack.md#99-market-sizing-tamsamsom).
> This section is the short version; **where it differs from doc 9 or doc 11, those win.**

```
41.13m German private households                (Destatis Mikrozensus 2025)
  × 92% smartphone & weekly shop                 = 37.8m
  × 80% buy fresh food regularly                 = 30.3m   ← TAM, €878m/yr at €29
  × 45% report throwing food away often          = 13.6m   ← problem-aware
  × 15% would install a food app                 =  2.05m  ← SAM  ⚠️ STATED INTENT
  SAM value: €1.78m/yr subscription + €2.69m/yr hand-off ≈ €4.5m/yr

Berlin alone: ~97,000 installs ≈ €215k/yr at full saturation — BELOW break-even.
```

**Read this honestly: a good small business, not an obvious venture-scale one on subscription
alone.** Germany's household base is ~46% larger than the UK's (41.1m vs 28.4m), and the
Belegausgabepflicht makes capture materially easier — but the ceiling is still a ceiling, and
venture scale needs the transaction leg ([§6.3](#63-the-second-revenue-leg-which-turned-out-to-be-the-first))
or DACH-wide reach.

**Why Berlin first — four reasons, one decisive**
1. ⭐ **The Belegausgabepflicht.** Since 1 Jan 2020, German law requires a receipt for *every*
   till transaction, even unwanted ones. **Every German shopper is handed the input to our
   product, several times a week, by law.** No other major market does this.
2. **Ten receipt templates cover ~80% of German grocery spend** (Edeka, REWE, Lidl, Aldi Nord,
   Aldi Süd, Kaufland, Penny, Netto, dm, Rossmann). The UK needs ~7; the US needs hundreds.
3. **Berlin has non-dilutive founder funding** — EXIST-Gründerstipendium (€2,500/founder/month),
   Berlin Startup Stipendium (up to €2,200/month), IBB Ventures B# Pre-Seed (€100k–400k).
4. **Berlin is Europe's most competitive online-grocery city** — Flink, Picnic, REWE, Knuspr,
   Flaschenpost, Amazon — which is where the revenue model actually works. Germany's *national*
   online-grocery share is only ~2.4%.

> ⚠️ **And the honest counterweight: Berlin's demographics are wrong for our primary customer.**
> Berlin is **50% single-person households** and averages 1.76 persons against 2.01 nationally.
> Waste concentrates in families; adoption concentrates in singles. Recruiting in
> Friedrichshain-Kreuzberg (59.2% single) would reproduce the category's canonical selection-bias
> failure while feeling like traction. **Phase 0 recruits in Marzahn-Hellersdorf, Spandau,
> Reinickendorf and the Brandenburg commuter belt, targeting ≥16 of 25 households with children.**

## 6.2 Business model — redrawn after review, re-priced for Germany

> ⚠️ **The original free/paid line was backwards in both directions.** Free got 4 receipt scans a
> month — calibrated to a 4.3-shop month, so it *both* maximised our cost and barely failed the
> user. And **everything retentive was paid**: sharing, import, don't-buy list, ideas and sweep.
> The free tier was therefore the *least* retentive version of the product, and free users churned
> before they could convert.

**The principle now: free contains the habit, paid contains the leverage.**

| Tier | Price | Contents |
|---|---|---|
| **Free** | €0 | Unlimited items, **unlimited tap/type capture, 2 receipt scans/mo**, the weekly alert, the don't-buy list, **one household partner** |
| | | ⚠️ *The 2-scan cap was set when a scan cost ~€0.06. With VLM-first parsing at ~$0.0008 ([doc 12](12-technical-research-capture.md)) **the cap is no longer a cost decision** — a free active household costs ~€0.006/month. Keep it, raise it, or drop it on **packaging** grounds, and test it; do not defend it on economics that no longer hold.* |
| **Plus** | **€29/yr** (annual-first) or €3.49/mo | Unlimited receipt scans, forward-to-address import, the sweep, rescue ideas, multi-source capture, the monthly savings artifact |
| **Haushalt** | €47/yr | Plus + up to 6 members, multi-kitchen |
| **Lifetime** | €69 one-off | KitchenPal's $29.99 lifetime sat unexamined in our own competitor table. **One-off pricing is what converts in low-salience utility categories**, and it sidesteps the renewal-audit problem entirely |

**Annual-first is deliberate**: for a low-salience product touched four times a month, moving the
renewal decision to once a year is a structural advantage.

🇩🇪 **Two German requirements that are not optional.**
**(1) PayPal + SEPA Lastschrift on web checkout.** German card penetration is ~11% of online
purchases — the lowest of any major Western economy — while PayPal is ~28% and SEPA Direct Debit
~17%. Card-only checkout would silently halve conversion, and app-store IAP is card-centric.
Web-first also avoids the 15–30% store cut, which is where the margin improvement in
[§9.6](09-investor-pack.md#96-unit-economics) comes from.
**(2) A compliant Kündigungsbutton** — Germany requires a one-click cancel for online
subscriptions. Annual-first pricing raises the stakes. Ship it before the paywall.

⚠️ **The hardest fact in the German market: the price is anchored at zero.** foodsharing.de is a
free volunteer network and the BMLEH ships a free "Zu gut für die Tonne!" app. **Our paid tier
must be justified by convenience, never by virtue** — a "do good" pitch competes with a volunteer
movement and loses.

**Still to solve:** a satisfied free user has no forced reason to convert. The intended pull is the
**savings artifact** — a monthly *"du hast 9 Sachen gerettet, ~€14"* — the only thing that makes
renewal legible for a product this quiet. Our copy guide currently forbids anything that sounds
like tracking; that rule needs a carve-out for user-initiated review.

## 6.3 The second revenue leg, which turned out to be the first

Too Good To Go's lesson: the money is in a **transaction**, not a subscription.
⚠️ **And the unit economics in [§9.6](09-investor-pack.md#96-unit-economics) upgraded this from
"second leg" to "the model". After the VLM-first margin correction
([doc 12](12-technical-research-capture.md)) subscription alone yields **2.1×; with the hand-off,
3.1×** — the hand-off is what clears the 3× threshold.** Candidates, ranked by strategic fit:

| Option | Revenue | Trust risk | Verdict |
|---|---|---|---|
| **Grocery basket hand-off** — *"die 4 fehlenden Zutaten in deinen Flink-/REWE-/Knuspr-Warenkorb"* (affiliate/commission) | ~€2.20 per basket (5% of ~€44) | Low, *if* recommendations stay honest | ✅ **Still the necessary one — it is what takes LTV/CAC from 2.1× to 3.1×.** Berlin is Europe's densest quick-commerce city, which is the real reason to launch there. ⚠️ **It does not travel: German online grocery is ~2.4% nationally**, so national rollout raises volume and *lowers* per-user economics |
| Anonymised, aggregated waste insights sold to CPG/retail | High | **High** | ❌ Contradicts our privacy promise. Do not. |
| Brand-sponsored rescue recipes | Medium | Medium | ⚠️ Only with clear labelling |
| B2B white-label for retailers / appliance makers | High, lumpy | Low | ⚠️ Real option, but a different company. Revisit at Series A |
| Impact/ESG reporting for corporate wellbeing programmes | Medium | Low | ⚠️ Interesting niche, month 18+ |

**Decision:** subscription is the v1 model. Grocery hand-off is the planned second leg.
Data resale is permanently off the table — it is written into the privacy policy, and that
constraint is itself a marketing asset.

## 6.4 Roadmap — Phase 0 inverted, Berlin first

> **The dated Gantt now lives in [§11.8](11-germany-berlin-market.md#118-revised-roadmap--berlin-first)**
> so there is one authoritative schedule. This section states the reasoning behind it.

> ⚠️ **The single most valuable recommendation from either reviewer.** Phase 0 originally led with
> *"can we parse receipts to 85% F1"* — *"the engineering-shaped, fun, cheap-to-be-confident-about
> question, and honestly the one you already know the answer to post-LLM. Bet 1 is not what kills
> you."*

### Phase 0 leads with a human concierge — ~€18k, six weeks, no code at all

**25 high-waste Berlin households**, recruited in **Marzahn-Hellersdorf, Spandau, Reinickendorf
and Treptow-Köpenick** — *not* Kreuzberg — with **≥16 of 25 having children**. A WhatsApp group.
Humans parsing photographed Bons by hand. Humans sending the Wednesday message. Measure two things:

| Measure | Why it is the whole business |
|---|---|
| **Capture compliance, week 1 vs week 6** | The number everything rests on, and there was previously **no plan to measure it before spending €600k** |
| **Rescue-on-prompt rate** | When a *perfect*, human-generated, perfectly-timed message arrives, what fraction actually cook the thing? **Software can only be worse than a human concierge — so this is the ceiling** |

**Pass:** compliance above ~60% at week 6 **and** rescue-on-prompt above ~40%.
**Fail:** we have saved ~€600k and a year.

The reviewer's prediction, recorded so we can score it: *"compliance decays to the 30s and the
rescue rate lands in the 20s, and the useful finding will be that the households who stayed
engaged did so because someone was telling them **what to cook**, not what they owned."*

Running alongside, not before: the **200-receipt German corpus across 10 chains**, the parser
spike, the **DSGVO DPIA** (Art. 35 requires it *prior to* processing, and beta starts in
February), the **Open Food Facts ODbL legal opinion**, and the **EXIST / Berlin Startup Stipendium
applications**, which take ~6–10 weeks and should be submitted first.

⚠️ **Four zero-or-near-zero-cost tasks added from [doc 12](12-technical-research-capture.md)**, all
of which piggyback on observations the concierge test already makes:
1. ~~Verify the TSE QR payload~~ — ⚠️ **done, and the answer was no.** The QR carries the till
   serial, transaction number, signature counter, timestamps and signature: **no amounts, no VAT
   subtotals.** It cannot validate an extraction. It survives as free **duplicate detection** and
   an **exact purchase timestamp**, which is what makes a Bon scanned days late safe.
2. **Count magnet-compatible fridge fronts** — 30 s per household. German *Einbauküchen* hide the
   door behind a wooden cabinet front, and 304 stainless is non-magnetic; if compatibility is under
   ~60% the door-mount idea is dead before any code is written.
3. **Film the unpacking** (with consent) and hand-label it later — a **real-kitchen CV dataset for
   free**, which answers the camera-capture question with **no CV code written**.
4. **Watch what actually happens in those 90 seconds** — this settles the "wave goods past the
   camera" and door-mount proposals with evidence rather than argument.

**Why DACH before the UK:** Austria and Switzerland share the language and most chains
(REWE/Billa, Lidl, Aldi/Hofer, Spar), so the marginal cost after Germany is small. **The UK now
needs a different capture strategy entirely** — no Bonpflicht, and a far higher online-grocery
share — making it a second product motion rather than a translation.

## 6.5 Go/no-go and kill criteria

| Gate | When | Pass condition | If failed |
|---|---|---|---|
| **G1 — Demand first, then feasibility** | End of Phase 0 | **Capture compliance ≥60% at week 6** *and* **rescue-on-prompt ≥40%** in the Berlin concierge test, **with the family-household cohort reported separately** — *then* ≥85% item F1 on a **defined** metric across 10 German chains. ⚠️ *n=25 gives a ±19pp CI; this is a directional judgement, not a hard threshold, and it is stated as such rather than pretending to precision. Include a no-prompt control arm — a two-week observed diary study about food waste measures the Hawthorne effect at least as much as the intervention* | Stop, or take the "what's for dinner" reframe seriously |
| **G2 — Retention** | End of closed beta | **W3 retention ≥35%** on the *value-received* definition, **on n≈400 and stratified by platform, push status and — critically in Berlin — household size**. ⚠️ *Berlin is 50% single-person households; without that cut, the singles cohort will flatter the number and hide the primary segment's real behaviour.* ⚠️ *Corrected: at n=100 the 95% CI is ±9.5pp — the gate could not distinguish 35% from 26% or 44%. And a hand-recruited beta cohort typically retains 2–3× the eventual organic cohort, so read this as a ceiling, and re-gate on cold-acquired users before scaling spend* | Do not launch. Fix the loop or stop |
| **G3 — Willingness to pay** | 8 weeks post-launch | Trial→paid ≥ 5%, gross churn ≤ 8%/mo | Re-price, or move to the grocery-hand-off model as primary |
| **G4 — Unit economics** | ⚠️ **Moved to closed-beta week 4** (was month 9, i.e. after launch) | Cost per **paying** household tracked from day 1; LLM fallback rate trending down from its ~100% cold start | Cut the free receipt allowance further, or gate receipts behind paid entirely |

**Explicit kill criterion:** if W12 retention is below 12% after two serious iterations of the
core loop, the product does not work and the team should stop. Writing this down now, while
nobody is emotionally invested, is the cheapest decision we will ever make.

## 6.6 Team & cost

| Phase | Team | Duration | Burn |
|---|---|---|---|
| Phase 0 | 2 founders (grant-funded) + 1 senior eng | 8 wks | ~€75k |
| Phase 1 | +1 full-stack, +0.5 designer | 15 wks | ~€185k |
| Phase 2 | same (~4.5 FTE) | 12 wks | ~€150k |
| Phase 3 | +1 growth, +0.5 data | 20 wks | ~€290k |
| **Year 1 total** | peak ~6 FTE | | **~€700k gross** |

> ⚠️ **The original UK-based £620k plan was under-modelled by roughly £100–150k**, and the same correction
> applies here. Per-head burn declined 40% across the year while the team got *more* senior, and
> these lines were missing entirely: **marketing** (a public launch and a paid tier with no
> marketing budget), analytics/experimentation infra, eval-set maintenance and ongoing labelling,
> **admin/support tooling** — the human-in-loop mitigation implies up to **5,000 receipts/month of
> review with nobody assigned** — on-call, **German localisation and copy**, security review, the
> **German shelf-life curation person-month**, and **beta recruitment** (400 real cooking
> households with no marketing budget is 3–4 weeks of someone's full time, previously owned by
> nobody).

**Revised year 1: ~€700k gross, of which ~€110k is covered by EXIST / Berlin Startup Stipendium**
→ **~€590k of actual cash burn.** Burn is back-loaded; Phase 3 runs at roughly a €750k/yr rate.

### The raise, reconsidered — and improved by Berlin
Both the bottom-up TAM and a reviewer's fund verdict pointed the same way: **a large equity raise
against a €2–3m ARR ceiling structurally mismatches the outcome** and forces a year-three B2B
pivot that is a different company.

**Berlin's funding stack lets us do better than resizing an equity round.**
**€360k total: ~€110k non-dilutive (EXIST / Startup Stipendium) + €250k IBB Ventures B#
convertible.** Only €250k is dilutive, and the convertible defers a valuation argument that
[§10.8](10-frameworks-and-financials.md#108-discounted-cash-flow) shows the cash flows do not
support anyway. Full breakdown: [§11.7](11-germany-berlin-market.md#117-the-revised-ask).

## 6.7 Go-to-market

| Channel | Rationale | Priority |
|---|---|---|
| **German content/SEO** (*"Wie lange hält Brokkoli im Kühlschrank?"*, *"MHD oder Verbrauchsdatum?"*) | Evergreen, high-intent, and maps exactly to our data asset. **German-language SEO is less contested than English**, which partly offsets the AI-Overviews problem below | **P0** |
| Short-form video: the 30-second Bon-scan demo | Genuinely satisfying to watch — and the **Bonpflicht paper-waste grievance is a native German hook**: *"Wir machen den Bon endlich nützlich"* | P0 |
| Partnerships: **Berliner Bezirke, BMLEH "Zu gut für die Tonne!", Verbraucherzentrale, Wohnungsbaugenossenschaften** | Credibility and distribution; German public bodies actively fund waste-reduction comms, and **the awareness vocabulary already exists** — we don't have to teach Germans that food waste matters | **P0 in Germany** (stronger than the UK equivalent) |
| Assistant-native surface (MCP for Claude/ChatGPT) | Pantry Persona proved the channel; near-zero install friction | P1 (cheap experiment) |
| Referral: "invite your household" | Sharing is a retention mechanic *and* a growth mechanic | P1 |
| Paid social | **€140 CAC against a €29 subscription LTV — structurally unviable.** Retargeting only, if ever | ❌ |
| Appliance/retailer B2B | Different sales motion; revisit post-PMF | P3 |

> ⚠️ **Recomputed after review.** The original claimed LTV ≈ £45 at 6%/mo churn — top-decile
> consumer-subscription territory. Net of payment fees and 19% VAT, €29/yr is **€23.40**, and at a
> realistic **8%/mo churn subscription-only LTV was €29, not €45.** Then
> [doc 12](12-technical-research-capture.md) cut parsing cost ~40× and gross margin rose 66% → 95%,
> taking **subscription-only LTV to €42 (2.1× CAC) and the blended figure to €61 (3.1×)** — the
> first version of the model that clears the 3× threshold. **The "blended" CAC is still really an
> *organic* CAC**, which by definition doesn't scale, and **paid acquisition still does not work at
> this price point** (€140 CAC via paid social). The plan says so plainly rather than assuming a
> blend it cannot buy.

> ⚠️ **The SEO thesis is dated.** *"Wie lange hält Brokkoli im Kühlschrank"* is precisely the
> query class Google's AI Overviews now answers **without a click** — though German-language
> queries are somewhat less saturated than English ones. Betting our only affordable
> acquisition channel on zero-click informational queries needs a much harder look — and no
> credible replacement has been identified yet, which is itself a finding.

## 6.8 Competitive response plan

| If… | Then… |
|---|---|
| NoWaste.ai ships identical zero-entry UX | Compete on the doctrine they can't retrofit: auto-retirement, uncertainty-honest freshness, notification restraint. These are hard to add to an app whose users already expect a complete list. |
| Samsung/LG bundle this into fridges | Non-overlapping market (new-appliance buyers ≈ 3%/yr). Consider being their software partner. |
| A retailer launches it free inside their own app | Real threat, but single-retailer only. Our value is cross-retailer + privacy. Accelerate the "we never sell your data" positioning. |
| An LLM assistant does it natively | Be there first via MCP. Own the *data layer* (household shelf-life priors), not the chat surface. |
| **foodsharing.de or the BMLEH app adds inventory tracking** | Both are free and civic; neither can plausibly build receipt parsing, consumption inference or a commercial hand-off. Compete on convenience, never on virtue — **we lose a virtue contest to a volunteer movement.** |
| **An investor raises SirPlus** | They will. Answer directly: SirPlus was *redistribution with physical stores and inventory risk*; we are *prevention with no inventory and no logistics*. The failure mode that killed it is not one we can have — and its insolvency is evidence for [§8.3](08-why-the-category-underperforms.md#83-the-comparison-that-explains-everything), which is the argument we are making anyway. |
| **Flink / REWE build it into their own app** | Single-retailer only, and structurally conflicted — they profit from over-purchase. Our value is cross-retailer plus a credible refusal to sell shopping data, **which is worth more in Germany than anywhere else.** |

## 6.9 The three bets, stated plainly

0. ⚠️ **Bet 0, which we had not written down: people will keep capturing, and will act when
   prompted.** Reviewers identified this as the real existential bet — not parsing. Testable for
   ~€18k in the Berlin concierge test, with no code.
1. **Passive capture is now good enough.** Post-LLM receipt parsing crosses the threshold that
   made this impossible in Kitche's era — **and Germany's Belegausgabepflicht guarantees the input
   exists.** *(Cheap to establish, and probably true — which is exactly why it should not have
   been the lead question.)*
2. **An inventory allowed to be wrong retains better than one required to be right.**
   Auto-retirement and uncertainty-honest freshness break the drift→distrust→churn spiral that
   killed the category. *(Testable in beta — G2.)*
3. **One well-timed weekly notification is worth more than a whole inventory app.** The RCT
   evidence says moment-of-decision prompting works (~30% reduction) and information alone
   doesn't. *(Testable in the diary study, before any code.)*

If bet 1 fails, the product is impossible. If bet 2 fails, we are the next headstone in
[§1.2](01-market-competitive-research.md#12-the-graveyard-15-years-of-attempts). If bet 3
fails, we are a nicer-looking pantry list.
