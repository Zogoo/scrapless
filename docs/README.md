# Crisper — Product & Business Documentation

Working name: **Crisper** — a responsive web app (PWA-first) that tells a household what food it
has and what is about to die, with as close to zero manual input as possible.

**Launch market: Berlin → Germany → DACH.** German law (Belegausgabepflicht) hands every shopper a
receipt on every transaction — the best capture substrate in Europe. See [doc 11](11-germany-berlin-market.md).

> **One-line thesis:** Every previous app in this category died of the same disease —
> *manual entry and inventory drift*. The product is not an inventory manager.
> It is a **rescue engine** that happens to keep a rough inventory.

## Document map

| # | Document | What it answers |
|---|----------|-----------------|
| 0 | [Executive summary](00-executive-summary.md) | Should we build this? What exactly? What's the bet? |
| 1 | [Market & competitive research](01-market-competitive-research.md) | 15 years of attempts, who died, who lives, why |
| 2 | [UX & behavioural research](02-ux-behavioural-research.md) | What the science says about lazy users and logging |
| 3 | [Product strategy & PRD](03-product-strategy-prd.md) | The product, scoped, with acceptance criteria |
| 4 | [UI screens & flows](04-ui-screens-flows.md) | Every screen, wireframed, plus state machines |
| 5 | [Technical architecture](05-technical-architecture.md) | Stack, data model, ML pipeline, cost model |
| 6 | [Business plan & roadmap](06-business-plan-roadmap.md) | Money, milestones, hiring, risks, kill criteria |
| 7 | [Senior staff engineering review](07-engineering-review.md) | Independent review + what we changed |
| 8 | [Why the category underperforms](08-why-the-category-underperforms.md) | The research on why these apps fail, and the nine gaps in the market |
| 9 | [Investor pack](09-investor-pack.md) | Customer, market, channels, CAC, unit economics, forecast, cash, the ask |
| 10 | [Frameworks & financials](10-frameworks-and-financials.md) | BMC, SWOT, Porter, PESTEL, P&L, break-even, scenarios, DCF, comps, cohorts |
| 11 | [Germany & Berlin market](11-germany-berlin-market.md) | **Canonical market figures.** Why Berlin, the German landscape, German operating differences, the revised ask and roadmap |
| 12 | [Technical research — capture](12-technical-research-capture.md) | **Canonical capture architecture.** VLM-first receipt reading, extraction-accuracy and hallucination evidence, the two German receipt checksums, EU data residency, Open Food Facts licensing, auto-capture, and the in-fridge/door-mount camera verdicts |
| 13 | [The MVP build](13-mvp-build.md) | **What now exists in this repo**, which conclusions it implements, and which it does not |
| 14 | [MVP cost model](14-mvp-cost-model.md) | What the OpenAI calls cost per receipt, per household, per month — and which model to use |

**Visual companion:** [Interactive product brief](https://claude.ai/code/artifact/bcd6a143-4d45-4464-af49-7a5f7e19a9e3) — screens, a draggable decay model, roadmap and gates.

## Reading order for a first-time reader
**0 → 11 → 12 → 8 → 9 → 7 → 2 → 3 → 4.** Read doc 7 in context: two senior reviewers found problems that changed the plan
materially, and every other document now carries ⚠️ markers where it was corrected.
Documents 1, 5, 6, 10 are reference depth.

## Precedence, when documents disagree
1. **[Doc 11](11-germany-berlin-market.md)** — canonical market, currency and geography figures
2. **[Doc 9](09-investor-pack.md)** — canonical unit economics, metrics ladder and the ask
3. **[Doc 12](12-technical-research-capture.md)** — canonical capture architecture and parsing cost
4. **[Doc 3](03-product-strategy-prd.md)** — canonical scope and acceptance criteria
5. Everything else

All figures are in **€**, German VAT **19%**, except where doc 7 quotes the original reviewers
verbatim — their £ figures are preserved deliberately, because editing a reviewer's numbers to
match a later decision would misrepresent the review.

## Status
⚠️ **There is now code.** A working MVP of the core loop lives in this repository — see
[doc 13](13-mvp-build.md). It does not overturn the decision gate below: it exists so the
concierge test can put a real thing in front of households, and so the model calls can be
priced against a real invoice.

Research and planning complete, reviewed by two independent senior engineers, re-based on a
Berlin launch, and the capture architecture rebuilt around a vision LLM.
**Nothing launches** until the Berlin concierge test reports.
Decision gate: [§ Go/No-go](06-business-plan-roadmap.md#65-gono-go-and-kill-criteria).
