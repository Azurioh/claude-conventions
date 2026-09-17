---
name: app-rules
description: Generates the project-specific rules of one app (or of the single app of a single-app repository) by analysing its code — rings, composition root, import boundaries, external dependencies behind ports, test layout, generated code, recurring patterns — and writes .claude/rules/<app>/architecture.md, optionally conventions.md, the <app>-dev agent and the app's rows of the Test layout table, after showing a preview and waiting for confirmation. Use after /conventions:port-claude-config has written the generic rules, when a repo has no .claude/rules/<app>/architecture.md, or when the user asks for project or app rules ("write the rules for <app>", "document the architecture of <app>").
argument-hint: "<app-name> | all"
---
Never commit. Never write a file before the user has confirmed step 3. Every path below is relative to the repo root (`git rev-parse --show-toplevel`). The generic rules are already written by `/conventions:port-claude-config`; this skill adds only what is specific to the app and cannot be derived from the generic rules or from the code itself.

## Step 1 — resolve the app

```bash
[ -d .claude/rules ] || echo "no .claude/rules — run /conventions:port-claude-config first"
jq -r '.apps // {} | to_entries[] | "\(.key)\t\(.value)"' .claude/conventions.json
```

- No `.claude/rules/` → stop with that message; nothing else runs.
- `apps` non-empty → `$ARGUMENTS` is one key (its path is the app dir) or `all` (run steps 2–4 once per app, one confirmation per app). Anything else → stop with `unknown app <x>; known: <keys>`.
- `apps` empty → single-app repo, the app dir is `.`, `$ARGUMENTS` is ignored. Targets change: `.claude/rules/app.md` instead of `.claude/rules/<app>/architecture.md` (the generic `architecture.md` already exists), `.claude/rules/conventions.md` instead of `.claude/rules/<app>/conventions.md`, `.claude/agents/app-dev.md` instead of `.claude/agents/<app>-dev.md`, no `paths:` frontmatter (they always apply). Say so in the preview.
- Read the app's existing sheet when present (`.claude/rules/<app>/commands.md`, single-app `.claude/rules/commands.md`): its sequence is what the agent runs, and it names the generated inputs and the dead-code checker.

## Step 2 — analyse with evidence

Every finding below carries a `file:line` (or a directory). A claim without one does not reach the preview. Run from the repo root with `APP` = the app dir.

- **Layout and rings actually present**: `find "$APP/src" -maxdepth 2 -type d | sort`. A ring is a top-level dir whose name or content says domain / application / infrastructure / transport / UI — or whatever split the app really has (feature modules, `core`/`server`/`client`, …). Describe the split that exists, not the one the generic rules describe.
- **Composition root(s)**: the file(s) that name concrete adapters next to the use cases they serve — usually `container`, `composition`, `bootstrap`, `main`, `app`. `grep -rln "infrastructure" "$APP/src"`, keep the importers that are not adapters themselves.
- **Lint-enforced import boundaries**: `biome.json*`, `eslint.config.*`, `.eslintrc*` at the app or repo root — `noRestrictedImports`, `no-restricted-imports`, `import/no-restricted-paths`, boundary plugins — and `tsconfig*.json` `paths` (aliases are how rings are named in imports). Record the config `file:line`, or `none — not enforced`.
- **External dependencies and where they are reached**:
  ```bash
  for d in $(jq -r '.dependencies | keys[]' "$APP/package.json"); do
    grep -rlE "from ['\"]$d(/|['\"])" "$APP/src" | sed 's#/[^/]*$##' | sort -u | sed "s#^#$d: #"
  done
  ```
  A DB driver, ORM, HTTP client, queue, SDK, mailer, filesystem or clock imported outside the adapter ring is a finding. For each vendor: which interface (port) hides it, and where is the in-memory twin the tests use?
- **Test layout**: runner config (`vitest.config.*`, `jest.config.*`, `playwright.config.*`, `pytest.ini`, …); `find "$APP" -path '*/node_modules' -prune -o \( -name '*.test.*' -o -name '*.spec.*' \) -print | sed 's#/[^/]*$##' | sort | uniq -c`; integration prerequisites: `process.env` / `os.environ` reads under the test dirs, `docker-compose*.yml`, `.env.example`, a `skip` guarded by an env var.
- **Dead-code tool**: the sheet's sequence, else `jq -r '.scripts' "$APP/package.json"`.
- **Generated code**: scripts named `generate`, `codegen`, `build:*` that write inputs the type check needs; `.gitignore` lines under the app; a `generated/` dir.
- **Recurring patterns**: factory prefixes — `grep -rhoE 'export (const|function) [a-z]+[A-Z][A-Za-z]*' "$APP/src" | sed -E 's/.* ([a-z]+)[A-Z].*/\1/' | sort | uniq -c | sort -rn | head`; error hierarchy — `grep -rn 'extends [A-Za-z]*Error' "$APP/src"`; module or route registration lists; file naming per ring.
- **Already documented**: the app's README, `docs/`, ADRs naming the app (`jq -r '.adrDir // "docs/adr"' .claude/conventions.json`), and `.claude/rules/architecture.md` — a rule already stated there is never repeated in the app file.

## Step 3 — propose, then STOP

Print, in this order, and nothing else:

1. **Evidence** (≤ 10 lines): app dir, rings found with their directories, composition root(s), lint boundary config (or `none — not enforced`), vendors imported outside the adapter ring (or `none`), test runner + dirs + prerequisites, dead-code tool, generated inputs.
2. **Observed vs intended** — every place where the code contradicts the architecture it seems to intend (a vendor import in the domain, a ring skipped, an adapter with no port, a test dir the runner does not pick up, a port with no in-memory twin): one line each, `file:line — observed … — intended …`, followed by the question **which one becomes the rule?** Never canonise the violation silently; never write the intended rule as if it held. None → say `none`.
3. **Preview of each file**, in a fenced block, exactly as it will be written:
   - `.claude/rules/<app>/architecture.md` — frontmatter `paths:` listing `<app-path>/**` as in the app's `commands.md` (multi-app only), title `# <app> — architecture`, then: a ring table (`Ring | Directory | May import | Must never import`), the composition root(s), the dependency direction and the forbidden imports with the lint rule that enforces them (or the statement that nothing does), the ports and where their in-memory twins live, the test requirement per ring, and what a change to an adapter must ship with (its integration test, its migration, its env var in the example file). One line per fact, evidence path kept on the line.
   - `.claude/rules/<app>/conventions.md` — only when step 2 found **at least 3** recurring, non-obvious patterns (a factory naming scheme, a registration list, an error hierarchy, a localisation rule, a migration discipline). Fewer → not written, say so.
   - `.claude/agents/<app>-dev.md` — frontmatter `name: <app>-dev`, `description` (implements one well-specified change in `<app-path>` following `.claude/rules/<app>/`, then runs the app's `commands.md` sequence; use for `<app>` work instead of a generic implementer), `tools: Read, Edit, Write, Grep, Glob, Bash`, `model: sonnet`. Body: scope = the task given; search before creating; tests first per the ring table; the sheet's sequence verbatim, all green before reporting; `/conventions:test-gaps <app>` before reporting; never commit; report ≤ 30 lines.
   - **Test layout rows** to append to the table in `.claude/rules/architecture.md` (columns `layer | source glob | test dir | test kind`, paths relative to the app dir): one row per ring that has a test dir; `test kind` = `unit` (in-memory twins), `integration` (real infrastructure — name the env var in the row when one is needed), `contract` (routes), `e2e`, or `none` when no runner covers the ring. Rows already present with the same layer and glob are not repeated.

   A target file that already exists is shown as a `diff` against its preview, with the question `replace` / `keep`.

   Each file ≤ 40 lines. Apply the drop rule to every line: **a line that restates what any reader sees in the code is dropped** (a directory listing, a function's signature, what a library does); what stays is a constraint, a boundary, a prerequisite or a trap. Tooling named only when step 2 found it.

Then **STOP and wait for the user's confirmation and their answers to the observed-vs-intended questions**. Do not write, render or run anything else in this turn.

## Step 4 — write (after confirmation only)

1. Write the previewed files, with the observed-vs-intended answers applied (`mkdir -p .claude/rules/<app> .claude/agents`). A file the user chose to `keep` is not touched.
2. Append the Test layout rows after the last row of the table in `.claude/rules/architecture.md` — the table sits outside the `<!-- conventions:begin … -->` / `<!-- conventions:end … -->` sentinels and belongs to the project; existing rows are never edited or reordered.
3. Check, then report:
   ```bash
   grep -n 'TODO\|<app>\|<app-path>' .claude/rules/*/architecture.md .claude/rules/*/conventions.md .claude/rules/app.md .claude/rules/conventions.md .claude/agents/*-dev.md 2>/dev/null
   git status --short
   ```
   Any hit is a slot left unfilled — fix it before reporting.

Report (≤ 15 lines): the files written, the rows appended, the observed-vs-intended decisions taken, `/conventions:test-gaps <app>` as the follow-up check, and `not committed — review with git diff, then commit yourself`.
