# Scrapless

A mobile-web app that tells a household what food it has and what is about to die,
with as close to zero manual input as possible.

Rails 8.1 API + Angular 21 PWA, SQLite, one Fly.io machine. The product research that
decides what this is and is not lives in [`docs/`](docs/README.md); the MVP build itself
is documented in [docs/13-mvp-build.md](docs/13-mvp-build.md), and what it costs to run
in [docs/14-mvp-cost-model.md](docs/14-mvp-cost-model.md).

> **Scaffolded from [project-preparator](../project-preparator).** Framework layout, Docker,
> CI and the agent docs come from the generator and were not modified there; the example
> CRUD it ships (users, notes, email/password auth) was removed and replaced by this domain.

## What it does

| | |
|---|---|
| **Identity** | No account. One optional question — "name your fridge?" — then a token in localStorage and a signed ten-year cookie. Either alone restores the fridge. |
| **Capture** | Point the camera and it fires the shutter itself; or say it; or type it. One endpoint, and the model works out whether it is looking at a receipt or at the shopping. |
| **Freshness** | Every item is a window with a confidence, never a date. `P(still present) × P(gone off)` decides what surfaces. |
| **Memo** | A shopping list that already knows you buy milk every four days and have not bought any for six. |
| **Install** | A real PWA: manifest, service worker, offline shell, add-to-home-screen. |

## Running it

Docker Compose is the intended path:

```bash
docker compose up
```

| Service | URL |
|---|---|
| App | http://localhost:4200 |
| API | http://localhost:3001 |

Without Docker, natively:

```bash
bundle install && bin/rails db:prepare && bin/rails db:seed
bin/rails server -p 3001
```

```bash
npm --prefix frontend install && npm --prefix frontend start
```

### The API key is optional

With no `OPENAI_API_KEY` the app runs against `Ai::Stub`: every screen works, receipts
"parse", and nothing is billed. That is deliberate — the UI has to be buildable and
demonstrable without an invoice attached. Set the key (in `.env`, see `.env.example`) to
go live; `/settings` then shows exactly what has been spent.

## Tests and checks

```bash
bundle exec rspec
```

```bash
npm --prefix frontend run test:ci
```

```bash
bundle exec rubocop && bin/brakeman && bin/bundler-audit
```

## Structure

```
app/
  controllers/api/v1/     fridges · items · captures · memo · costs
  controllers/concerns/   fridge_identifiable.rb — the whole auth system
  models/                 household · item · item_event · capture · memo_item ·
                          shelf_life_rule · product_alias · ai_call
  services/
    ai/                   config (models + prices) · client · image_reader ·
                          text_reader · transcriber · stub
    freshness/            estimator · presence_model · risk_scorer
    captures/ items/      ingest · resolver
    memo/ text/           suggester · splitter
    categories.rb copy.rb the food vocabulary, and the copy rules
frontend/src/app/
  core/vision/            frame-analysis · auto-shutter (the camera's own trigger)
  core/services/          fridge · items · capture · memo · speech · install
  features/               onboarding · today · capture · memo · kitchen · settings
```

## Where the design decisions come from

Nearly every non-obvious choice here traces to a specific finding in `docs/`, and the
code says which. Three worth knowing before changing anything:

- **The schema has no `expires_on`.** Items carry `window_start`/`window_end` so it is
  structurally impossible to render a precision we do not have.
- **Spoilage alone never fires an alert.** It is multiplied by `P(still present)`, or the
  app warns you about food you ate on Tuesday — the failure two reviewers said would sink
  the original design (doc 0).
- **Nothing asks the user to tidy up.** Stale guesses retire themselves.
