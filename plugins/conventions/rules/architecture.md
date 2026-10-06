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
- **A new layer, folder convention or cross-feature dependency** the rules do
  not cover → ADR first (`/conventions:adr`), code second.
<!-- conventions:end architecture.structure -->

<!-- conventions:begin architecture.ports -->
- **Ports and adapters everywhere.** Never reach an external dependency (DB,
  HTTP API, filesystem, clock, mail, vendor SDK) directly — go through a port
  owned by the application layer and named after the business need, not the
  technology; the adapter lives in infrastructure with an in-memory twin for
  tests. Swapping a service = a new adapter, nothing else.
- **Layers never call each other directly.** Direction is domain ← application
  ← infrastructure ← transport/UI; wiring only happens in the composition
  root named in the app's rules (`.claude/rules/<app>/`). No concrete import
  crosses a ring: a lint error there means move the code, never silence it;
  where no linter enforces the direction, the rule still applies.
- **Business decisions are pure domain functions** — a test of them needing a
  mock means logic leaked into an adapter. Use case: refuse → validate → act.
  Entities are immutable: a state change returns a new value, and creation
  goes through a factory that checks the invariants.
- **A use case has one entry point** and receives its ports as injected
  dependencies. It never calls another use case (extract a domain service)
  and never receives a request, a session or an ORM type.
- **Plain data crosses the boundaries.** Use cases take and return DTOs;
  entities never leave the application layer. Two mappings, one place each:
  contract ↔ DTO in the transport handler (validate → authorize → use case →
  map), domain ↔ persistence in the adapter's mapper.
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
- **Every change is tested.** Domain + application: written test-first, unit
  tests with in-memory twins, never mocks of internals. Adapters: integration
  tests against real infrastructure (a test that skips silently when its env
  var is unset does not count — set it, run it).
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
