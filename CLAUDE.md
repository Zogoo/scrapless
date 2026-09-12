# CLAUDE.md

Scrapless — a mobile-web app that tells a household what food is about to die.

Start with **[docs/13-mvp-build.md](docs/13-mvp-build.md)**: what exists, what deliberately
does not, and the one calibration constant that is load-bearing and unverified.

- [AGENTS.md](AGENTS.md) — the agent contract.
- [docs/README.md](docs/README.md) — the product research (docs 0–14). It is the *why* behind
  almost every non-obvious decision in the code, and the code cites it by section.
- [docs/engineering/](docs/engineering/) — the generic stack contract from the scaffold.

Two rules that are easy to break by accident:

1. **Never introduce an `expires_on`.** Items carry `window_start`/`window_end` so the UI
   cannot render a precision we do not have.
2. **Never surface spoilage without multiplying by `P(still present)`.** That is the
   correction the whole design rests on — see `app/services/freshness/risk_scorer.rb`.
