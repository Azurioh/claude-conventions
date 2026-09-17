# Architecture

<!-- conventions:begin architecture.ports -->
- **Ports and adapters everywhere.** Never reach an external dependency (DB,
  HTTP APIs, filesystem, clock, mail, third-party SDK) directly — go through a
  port (interface) owned by the application layer; the adapter lives in
  infrastructure, and an in-memory twin exists for tests. Swapping a service
  means writing a new adapter — domain and application never change.
- **Layers never call each other directly.** Dependency direction is domain
  ← application ← infrastructure ← transport/UI; wiring only happens in the
  composition root named in the app's rules (`.claude/rules/<app>/`). No
  concrete import crosses a ring. Where a linter enforces the direction, keep
  it enabled; where none does, the rule still applies.
- **No dead code.** No unused export, type, interface, parameter, feature
  flag, or "just in case" branch. When the app's `commands.md` names a
  dead-code checker, it is the judge and CI fails on it; elsewhere grep for a
  consumer before exporting. Delete it, never disable the rule.
<!-- conventions:end architecture.ports -->

<!-- conventions:begin architecture.testing -->
- **Every change is tested.** Domain + application: unit tests with
  in-memory twins. Adapters: integration tests against real infrastructure
  (a test that silently skips when its environment variable is unset does
  not count — set the variable and run it before reporting). Transport:
  route/contract tests. A PR touching source without a matching test must
  state why in its body.
- The **Test layout** table below is project-owned (`/conventions:port-claude-config
  --refresh` never rewrites it): keep it accurate, one row per layer, paths
  relative to the app directory. `/conventions:test-gaps`, the `test-writer`
  and `rules-reviewer` agents read it to know where a file's test belongs.
  The optional `other` row is the fallback for files matching no other glob.
<!-- conventions:end architecture.testing -->

## Test layout

| layer | source glob | test dir | test kind |
|---|---|---|---|
| domain | `src/domain/**` | `tests/domain` | unit |
| application | `src/application/**` | `tests/application` | unit |
| infrastructure | `src/infrastructure/**` | `tests/integration` | integration |
| transport | `src/transport/**` | `tests/transport` | contract |
| other | `src/**` | `tests` | unit |
