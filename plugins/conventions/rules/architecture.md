# Architecture

<!-- conventions:begin architecture.structure -->
- **Feature-first.** A feature owns its slice — `domain/` → `application/` →
  `infrastructure/` → transport/UI — under one directory. Code two features
  need lives in `shared/`, never in either of them.
- **One registration point.** A feature plugs in through one factory listed at
  the composition root (the on/off switch); nothing self-registers on import.
- **Injected, never global**: logger, clock, id generator, database, config.
  Config is parsed once at boot into a typed object; a missing or invalid
  variable stops the process before it serves. Nothing else reads the env.
<!-- conventions:end architecture.structure -->

<!-- conventions:begin architecture.ports -->
- **Ports and adapters everywhere.** Never reach an external dependency (DB,
  HTTP API, filesystem, clock, mail, vendor SDK) directly — go through a port
  owned by the application layer; the adapter lives in infrastructure with an
  in-memory twin for tests. Swapping a service = a new adapter, nothing else.
- **Layers never call each other directly.** Direction is domain ← application
  ← infrastructure ← transport/UI; wiring only happens in the composition
  root named in the app's rules (`.claude/rules/<app>/`). No concrete import
  crosses a ring: a lint error there means move the code, never silence it.
- **Business decisions are pure domain functions** — a test of them needing a
  mock means logic leaked into an adapter. Use case: refuse → validate → act.
<!-- conventions:end architecture.ports -->

<!-- conventions:begin architecture.boundaries -->
- **No cross-feature import**: a feature imports `shared/` and its own ports,
  never another feature; client code imports server code as types only
  (`import type`). Only infrastructure names a vendor (ORM, SDK, driver);
  only the composition root or the feature's factory picks the adapter.
- **Another app or service is consumed through its API** behind one fetch
  layer — that layer is the adapter; pages and handlers never call its SDK
  or import its source.
- **Concurrency invariants live in the database** (unique constraints,
  conditional updates); isolation + retry is the second line; a parallel test
  is the proof an in-memory twin cannot give. Effects that leave the
  transaction (notify, wake a worker) run after commit, never shape the result.
<!-- conventions:end architecture.boundaries -->

<!-- conventions:begin architecture.testing -->
- **Every change is tested.** Domain + application: unit tests with in-memory
  twins. Adapters: integration tests against real infrastructure (a test that
  skips silently when its env var is unset does not count — set it, run it).
  Transport: route/contract tests. A PR touching source with no test says why.
- The **Test layout** table below is project-owned (`--refresh` never rewrites
  it): one row per layer, paths relative to the app dir. `/conventions:test-gaps`,
  `test-writer` and `rules-reviewer` read it to place a file's test; the
  optional `other` row is the fallback for files matching no other glob.
<!-- conventions:end architecture.testing -->

## Test layout

| layer | source glob | test dir | test kind |
|---|---|---|---|
| domain | `src/domain/**` | `tests/domain` | unit |
| application | `src/application/**` | `tests/application` | unit |
| infrastructure | `src/infrastructure/**` | `tests/integration` | integration |
| transport | `src/transport/**` | `tests/transport` | contract |
| other | `src/**` | `tests` | unit |
