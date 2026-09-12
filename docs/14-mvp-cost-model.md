# 14. MVP Cost Model — what the OpenAI calls actually cost

*Companion to [doc 13](13-mvp-build.md). Every figure here is computed from the price
table in [`app/services/ai/config.rb`](../app/services/ai/config.rb), which is also what
the running app bills against — so this document and the `/settings` cost screen cannot
drift apart without one of them being wrong.*

> **Scope note.** [Doc 12](12-technical-research-capture.md) recommends Gemini 2.5 Flash on
> cost (~$0.0008/receipt). This build uses the OpenAI API by instruction. The gap is real
> and is quantified in §14.5 rather than hidden: **we are paying roughly 3× doc 12's
> recommended floor**, and at these absolute numbers that is a defensible trade.

---

## 14.1 Prices used

| Model | Job | Input $/1M | Output $/1M |
|---|---|---|---|
| `gpt-5-mini` | receipt and shelf-photo reading | 0.25 | 2.00 |
| `gpt-5-nano` | text and voice → items | 0.05 | 0.40 |
| `gpt-4o-mini` | *(configured, unused — the A/B candidate, §14.5)* | 0.15 | 0.60 |
| `gpt-4o-mini-transcribe` | speech → text | — | $0.003/minute |

---

## 14.2 Cost of one of each thing

**A receipt.** Client downscales to a long edge of ~2048 before upload, which is the single
biggest cost lever on this path — image tokens are area, so not doing it would roughly
quadruple the input side.

| | Tokens | Cost |
|---|---|---|
| Image (≈1536×2048, 32×32 patches, capped) | ~2,500 | $0.00063 |
| System prompt | ~300 | $0.00008 |
| Output — 30-line German Bon as JSON | ~900 | $0.00180 |
| **Per receipt** | | **≈ $0.0025** |

**A typed or spoken line** ("milk, broccoli, two chicken breasts"), *and only the part of it
the dictionary could not resolve for free*:

| | Tokens | Cost |
|---|---|---|
| Prompt + the unresolved words | ~250 | $0.0000125 |
| Output | ~120 | $0.000048 |
| **Per parse** | | **≈ $0.00006** |

**A voice note**, 15 seconds, **and only on iOS**. Chrome and Android do speech recognition
on the device for free, so this line is charged for roughly the Safari share of traffic:

| | | Cost |
|---|---|---|
| 0.25 min × $0.003 | | **≈ $0.00075** |

> **A receipt costs ~40× a text parse and ~3× a voice note.** That ratio is why the tiers are
> split the way they are, and why the shutter refuses to fire at a blank worktop
> ([`auto-shutter.ts`](../frontend/src/app/core/vision/auto-shutter.ts)): the expensive call
> is the one that must not be wasted.

---

## 14.3 Per household per month

Capture volume uses doc 2 §2.4b's honest compliance forecast — **25–35% of shops captured by
week 8** — not a first-week figure.

| | Typical household | Heavy household |
|---|---|---|
| Shops/week | 2.5 | 4 |
| Capture compliance | 30% | 100% *(the compliant outlier)* |
| Receipts/month | 3.3 | 17 |
| Text parses reaching a model/month | 1.6 | 10 |
| Voice notes billed/month | 0.9 | 8 |
| **Receipts** | $0.0081 | $0.0425 |
| **Text** | $0.0001 | $0.0006 |
| **Voice** | $0.0007 | $0.0060 |
| **Total / month** | **≈ $0.009** | **≈ $0.049** |
| | **≈ €0.008** | **≈ €0.045** |

**Against doc 12's model:** it budgets €0.02/month for receipt parsing inside a €0.11
fully-loaded COGS. A typical household here lands *under* that; a heavy one lands at about
twice the parsing line but still well inside the €0.11 envelope once infra is added. **The
unit economics in doc 12 survive the switch from Gemini to OpenAI.**

### What this means for the free tier

At $0.009/month, **1,000 free households cost about $9/month to serve.** That is the number
that makes an organic-only growth strategy survivable, and it is the reason doc 12 called the
cost correction "risk reduction, not volume".

---

## 14.4 The two things that keep the bill down, and one that does not

✅ **The dictionary.** [`ProductAlias`](../app/models/product_alias.rb) resolves receipt jargon
to real names for free, and every user correction adds an entry
([`items_controller.rb`](../app/controllers/api/v1/items_controller.rb) `#update`). On the
typed path this is the whole mechanism: `milch, brokkoli` costs **exactly nothing**, and only
a genuinely new word reaches the nano tier. Verified live — four items added through the tap
grid produced **zero** billed calls.

✅ **Client-side speech.** The browser's own recogniser costs nothing, so transcription is
billed for iOS only. If that path were used for everyone, voice would cost more than
receipts do.

❌ **What is *not* implemented: the second-pass tier.** Doc 12's pipeline sends only the ~15%
of receipts whose checksums fail to a stronger model. This MVP has no second pass and no
checksum reconciliation, so it is *simpler and cheaper than doc 12's design, and less
accurate*. That is the right trade for an MVP and the wrong one for launch — see doc 13's
gap list.

### Rate limiting

40 captures per hour per fridge, counted out of the `captures` table rather than a cache
counter so that a cache flush cannot reset a spending limit. A fridge costs nothing to
create and there is no account wall, so without this the worst case is unbounded: at
$0.0025 a call, a loop left running overnight is a real invoice.

---

## 14.5 Model choice — measured against the bill

| Option | $/receipt | vs current | Verdict |
|---|---|---|---|
| **`gpt-5-mini`** *(current)* | $0.0025 | — | Ships. Enough headroom on faded thermal paper. |
| `gpt-4o-mini` | $0.00096 | **2.6× cheaper** | ⭐ **Measure this first.** Already in the price table; switch with `AI_MODEL_RECEIPT_EXTRACT`. |
| `gpt-5-nano` | $0.0005 | 5× cheaper | ❌ Not for receipts. See below. |
| *Gemini 2.5 Flash (doc 12)* | $0.0008 | 3× cheaper | The known floor, outside this build's scope. |

**Why nano is refused for receipts and used everywhere else.** Doc 12 §12.1 measures a
20-point spread on the hallucination benchmark between specialised document models and
general VLMs, and makes the point that matters: *a hallucinated line item is worse than an
OCR error, because it reads as correct.* An invented "Hähnchenschenkel" on a Bon produces a
confident alert about food that was never bought — precisely the false-alarm failure that
this whole design is built to avoid. The saving would be **$0.002 per receipt, about $0.007
per household per month.** That is not a trade worth making against trust.

The same argument does not apply to the text path. "Two chicken breasts" has no visual
ambiguity and no faded print, so nano runs it.

**The decision rule, so this is not re-argued from opinion:** both candidates are in
`Ai::Config::MODELS` and switchable by environment variable. Run them against the
200-receipt German corpus doc 12 already calls for, compare line-level F1 and invented-line
rate, and let the corpus decide. Do not switch on price alone.

---

## 14.6 Measuring it in production

Every call writes an [`AiCall`](../app/models/ai_call.rb) row — model, tokens, micro-dollars,
duration, success — **including failures**, so the ledger cannot silently under-report. Cost
is stored as an integer number of micro-dollars, because floats do not add up over a million
rows.

`GET /api/v1/costs` and the `/settings` screen expose it in-product. That is deliberate: the
claim "a capture costs a fraction of a cent" is the load-bearing one in this document, and it
should be falsifiable by whoever is paying the invoice rather than taken on trust.
