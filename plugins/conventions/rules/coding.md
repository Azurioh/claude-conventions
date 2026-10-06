# Coding

<!-- conventions:begin coding.changes -->
- **Search before creating** (`ast-grep`, LSP, grep): reuse > extend > add new.
  Duplicating behaviour that already exists is a defect, not a style issue.
- **Stay in scope** (no drive-by refactor, rename or reformat — its own PR);
  library and API questions are answered from current docs, never memory.
- **Fit the existing architecture.** When the clean solution needs the
  structure reshaped, stop and surface the trade-off — never bolt on an
  exception. Adding a feature = copying the closest existing slice, layer by
  layer, plus its registration entry — never a fresh layout.
- **No scaffolding**: no placeholder, `TODO`, speculative branch, "just in
  case" flag, or unused export, type or parameter. Where `commands.md` names a
  dead-code checker it is the judge; elsewhere grep for a consumer first.
- **A schema change ships with its migration in the same PR** — never a
  permanent read-time fallback. The migration is idempotent and resumable
  (proven by a test), touches only its owner's tables, never edited after merge.
  Its SQL is read before applying: no unintended `DROP`, column removal, type
  narrowing or `NOT NULL` without a backfill.
- **Build clean before "done"**: zero errors and zero warnings across build,
  type-check, lint and tests — a warning left behind is a defect.
<!-- conventions:end coding.changes -->

<!-- conventions:begin coding.style -->
- **Brace every `if`/`else`**, even single-line. The loop exit condition is
  visible in the header — no `while (true)` with an inner `break`.
- **Path aliases over relative climbs**: `@/…`, never `../../`. Code,
  comments and identifiers are English.
- **Expected failures are one typed business error** (a kind that maps to a
  status, a code the caller branches on); anything else is logged with an
  incident reference and shown generically. Error classes live in `errors.ts`,
  never in the file that throws them. A `catch` never drops the cause.
- **No unexplained type escape** (`any`, a cast hiding a mismatch, `!`, an
  ignore comment). Comments say why, never restate the code.
- **Log through the injected logger**, never `console.*`; a secret or an
  auth header never reaches a log line.
- **User-facing text lives in a message catalogue**, never as a literal in a
  handler or component; the default-language entry is mandatory.
- **UI is mobile-first** (tap targets ≥ 44px, no hover-only affordance); a
  mockup is implemented pixel-perfect — ask on ambiguity, never improvise.
- **Factories are `create*`**; a feature's public entry is one file
  (`module.ts` / `index.ts`), the only file outside infrastructure that may
  name an adapter.
<!-- conventions:end coding.style -->

<!-- conventions:begin coding.dependencies -->
- **A vendor SDK appears only under infrastructure**; domain, application and
  UI depend on ports (adding one: `workflow.md`, exact pin through the
  package manager, never a hand-edited manifest).
- **Workspace packages are built before any app typecheck or build** — apps
  do not rebuild them on install. A change to a shared package or contract is
  a cross-app change: verify every consumer, not only the one you touched.
- **Generated files are never hand-edited** (ORM clients, import maps,
  vendored UI primitives): regenerate with their tool, keep them out of lint,
  and when they are not committed the verify sequence generates them first.
  Compose around a vendored component, never edit the file.
- **A major version bump of a toolchain piece** (language, bundler, framework)
  is its own PR; a ceiling recorded in `pitfalls.md` is not raised without
  re-running the case that set it.
<!-- conventions:end coding.dependencies -->
