# AGENTS.md — Scrapless

**Read `docs/` before making changes.** Note there are two sets: `docs/00`–`docs/14` are the
product research and the build record for *this* application; `docs/engineering/` is the
generic engineering contract that came from the scaffold generator. These files are the contract for how work is done
in this repository, for AI agents and humans alike.

| Doc | Read it when |
|---|---|
| [docs/13-mvp-build.md](docs/13-mvp-build.md) | **Always — first, for this app.** What exists, what does not, and the calibration that must be re-derived. |
| [docs/14-mvp-cost-model.md](docs/14-mvp-cost-model.md) | Touching anything in `app/services/ai/`, or choosing a model. |
| [docs/engineering/00-agent-persona.md](docs/engineering/00-agent-persona.md) | Always — first. Defines how you work and the definition of done. |
| [docs/engineering/01-tech-stack.md](docs/engineering/01-tech-stack.md) | Considering any dependency, or touching the DB. |
| [docs/engineering/02-architecture.md](docs/engineering/02-architecture.md) | Adding an endpoint, service, query, or component. |
| [docs/engineering/03-coding-standards.md](docs/engineering/03-coding-standards.md) | Writing any code. |
| [docs/engineering/04-security-owasp.md](docs/engineering/04-security-owasp.md) | Touching auth, params, uploads, or SQL. |
| [docs/engineering/05-testing.md](docs/engineering/05-testing.md) | Writing tests — which is every behaviour change. |
| [docs/engineering/06-workflows.md](docs/engineering/06-workflows.md) | Running commands, migrations, i18n, deploys. |

## The short version

- Senior Rails + Angular engineer. Boring, proven, tested.
- **Rails-native-first**: if Rails already does it, do not add a gem.
- **Nothing JS in Rails**: the SPA is Angular's, exclusively.
- **Never** `rails generate scaffold`; never hand-write a migration.
- **Always** scope records through `current_household` — the fridge is the tenant, not a user.
- Tests, RuboCop, Brakeman, bundler-audit green before done.

## Layout

```
app/{controllers,models,services,queries,jobs,mailers}   # thin → service → query → model
spec/                                                    # RSpec
frontend/src/app/{core,features,shared}                  # Angular standalone + signals
docs/                                                    # you are here
```
