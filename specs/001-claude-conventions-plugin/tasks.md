# Tasks: Claude Conventions Plugin

**Input**: Design documents from `/specs/001-claude-conventions-plugin/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md
**Tests**: requested — hook tests are written first (red) and drive the hook implementation (FR-013, plan phase 2).
**Reference**: `/Users/azurioh/Repositories/BSK/bsk-apps/.claude` (branch `docs/claude-config-spec`) — read the counterpart file before porting; never copy a bsk-specific identifier (`demo`, `main` as literal, `pnpm`, `biome`, `hub`, `bot`, `cms`, `website`, `Dokploy`, `knip`, `Prisma`, bsk paths) into `plugins/`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no dependency on an unfinished task)
- **[Story]**: US1 install · US2 port · US3 update/refresh · US4 value resolution

## Phase 1: Setup (Shared Infrastructure)

- [ ] T001 Create the repository layout from plan.md: `.claude-plugin/`, `plugins/conventions/{.claude-plugin,hooks,skills,agents}`, `plugins/conventions/skills/port-claude-config/{scripts,templates/rules}`, `schema/`, `profiles/`, `tests/fixtures/{pnpm-biome,npm-prettier,no-conventions}`, `.github/workflows/`; add `.gitignore` (OS/editor files only; `.specify/` and `specs/` stay committed) and `LICENSE` (MIT, Azurioh)
- [ ] T002 Write `.claude-plugin/marketplace.json` (`name: "claude-conventions"`, `owner.name: "Azurioh"`, one plugin `conventions` with `source: "./plugins/conventions"`, `version: "0.1.0"`, description) per research R1
- [ ] T003 [P] Write `plugins/conventions/.claude-plugin/plugin.json` (`name: "conventions"`, `version: "0.1.0"`, `description`, `author`) per research R1
- [ ] T004 [P] Write `plugins/conventions/hooks/hooks.json` registering the five hooks exactly as `contracts/hooks.md` (events, matchers, `${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh`, timeouts 10/10/20/30/5)
- [ ] T005 Run `claude plugin validate plugins/conventions` on the skeleton (scripts may be empty stubs with `exit 0`) and fix any manifest error before continuing
- [ ] T006 [P] Write `.github/workflows/ci.yml`: ubuntu-latest, install `shellcheck` + `jq`, run `shellcheck plugins/conventions/hooks/*.sh plugins/conventions/skills/port-claude-config/scripts/*.sh tests/*.sh` and `tests/run.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: shared shell library, test harness and first fixture that every hook depends on.

- [ ] T007 Write `tests/fixtures/pnpm-biome/`: `package.json` (name `fx-pnpm-biome`, `packageManager: "pnpm@…"` latest from registry, scripts `lint`/`test` echoing), `pnpm-lock.yaml` (minimal valid header), `biome.json` (formatter enabled), `.claude/conventions.json` (`integrationBranch: "develop"`, `productionBranch: "main"`, `apps: { "api": "apps/api" }`), `apps/api/package.json`, `src/index.ts` (unformatted on purpose)
- [ ] T008 Write `tests/run.sh` harness: `mkfixture <name>` (copy fixture to `mktemp -d`, `git init -q -b main`, initial commit, create integration branch), `bash_event <cmd>` / `edit_event <file>` (build stdin JSON with `tool_name`, `tool_input`, `cwd`), `expect <exit> <hook> <stdin> [stderr-substring]`, counters, `OK: N assertions` / non-zero on failure; export `CLAUDE_PROJECT_DIR` to the fixture; shellcheck-clean
- [ ] T009 Port `plugins/conventions/hooks/lib.sh` from the reference `hooks/lib.sh` (`split_segments`, `normalize_segment`, `git_strip_opts`, `flag_value_last`, `strip_quotes`) and add: `project_root` (`$CLAUDE_PROJECT_DIR` → `.cwd` → `git rev-parse --show-toplevel`), `conv_file`, `conv_get <jq-path> <default>` (missing file/key → default), `conv_require <jq-path> <hook>` (missing → stderr `conventions/<hook>: .claude/conventions.json missing — skipped`, returns 1), `detect_pm` (lockfile table from research R4, two lockfiles → empty), `detect_formatter` (biome / prettier / none per R4), `production_branch` (override → `origin/HEAD` → `main`), `in_git_repo`; shellcheck-clean

**Checkpoint**: `tests/run.sh` runs (0 assertions) and sources `lib.sh` without error.

---

## Phase 3: User Story 1 — Install the guardrails in one step (Priority: P1) 🎯 MVP

**Goal**: after `ccprofile apply conventions`, the five hooks are active and the generic skills/agents are available in a repo that declares its integration branch.

**Independent Test**: quickstart §2 on the `pnpm-biome` fixture — banner shown, force push and bare stash refused, non-pinned add refused, `.ts` edit formatted, oversized PR blocked; `/conventions:pr` listed.

### Tests for User Story 1 (write first, must fail)

- [ ] T010 [US1] Add `guard-git` assertions to `tests/run.sh` (pnpm-biome): `git push --force origin develop` → 2; `git push -f` → 2; `git push --force-with-lease` → 2; bare `git stash` → 2; `git stash pop` → 2; `git stash push -u -m x` → 0; `git commit -m x` on `main` → 2, on `feat/x` → 0; `gh pr create --base main` → 2; `gh pr create --base develop` → 0; `gh pr create --base main --head develop` → 0 (release pair); `ls` → 0
- [ ] T011 [P] [US1] Add `deps-exact` assertions (pnpm-biome): `pnpm add lodash` → 2 with stderr containing `-E`; `pnpm add -E lodash` → 0; `pnpm add --save-exact lodash` → 0; `pnpm add -D lodash` → 2; `pnpm install` → 0; `pnpm remove lodash` → 0
- [ ] T012 [P] [US1] Add `pr-size` assertions (pnpm-biome): 20 files × 1 line → 2 (files cap); 1 file × 401 lines → 2; 1 file × 400 lines → 0; oversize but `--label large-pr` → 0; oversize only in `pnpm-lock.yaml` and `apps/api/migrations/x.sql` → 0; release pair oversize → 0
- [ ] T013 [P] [US1] Add `format` assertions (pnpm-biome): edit event on `src/index.ts` → 0 and file content changed (formatted); edit event on `README.md` → 0 and untouched; missing file path → 0
- [ ] T014 [P] [US1] Add `branch-info` assertions (pnpm-biome): stdout contains the current branch name; on `main` stdout contains a warning line; outside a git repo → 0 and empty stdout

### Implementation for User Story 1

- [ ] T015 [US1] Port `plugins/conventions/hooks/guard-git.sh` from the reference, replacing literals by `conv_require integrationBranch` + `production_branch`; behaviour per `contracts/hooks.md`; fail open outside git / without conventions file; T010 green; shellcheck-clean
- [ ] T016 [P] [US1] Write `plugins/conventions/hooks/deps-exact.sh`: `detect_pm` override by `conv_get packageManager`; flag table pnpm `-E|--save-exact`, npm `--save-exact|-E`, yarn `--exact|-E`, bun `--exact|-E`; stderr suggests the corrected command; undetected PM → warning + exit 0; T011 green; shellcheck-clean
- [ ] T017 [P] [US1] Port `plugins/conventions/hooks/pr-size.sh` with `prSize.{lines,files,exclude,label}` from `conv_get` and the defaults of research R4; exclusion globs matched with `case`-style patterns on `git diff --numstat` paths; release pair skip; T012 green; shellcheck-clean
- [ ] T018 [P] [US1] Write `plugins/conventions/hooks/format.sh`: extension list from the reference; `detect_formatter` override by `conv_get formatter`; `<pm> exec biome check --write <file>` or `<pm> exec prettier --write <file>`; always exit 0, stderr only on formatter failure; T013 green; shellcheck-clean
- [ ] T019 [P] [US1] Port `plugins/conventions/hooks/branch-info.sh`: protected set `{production, integration}`; prints branch/upstream/warning on stdout; prints the conventions validation message when `integrationBranch == productionBranch` or file unparsable; T014 green; shellcheck-clean
- [ ] T020 [P] [US1] Write `plugins/conventions/skills/pr/SKILL.md` from the reference `pr` skill: bases and size cap read from `.claude/conventions.json` (quote the jq paths), stacked PRs via `gh stack link --base <integrationBranch>`, descriptive branch names, no app names; frontmatter `name`, `description`, `argument-hint`
- [ ] T021 [P] [US1] Write `plugins/conventions/skills/verify-app/SKILL.md`: apps from `conventions.json#apps` (absent → single app), sequence read from `.claude/rules/<app>/commands.md` (or `.claude/rules/commands.md`), forks into the global `verifier` agent (`context: fork`, `agent: verifier`), states the prerequisite in the description
- [ ] T022 [P] [US1] Write `plugins/conventions/skills/test-gaps/SKILL.md`: layer→test-dir mapping read from the target's `.claude/rules/architecture.md` "Test layout" table, output format MISSING/PRESENT per file, forks into `verifier`
- [ ] T023 [P] [US1] Write `plugins/conventions/skills/adr/SKILL.md`: directory `conv_get adrDir` default `docs/adr`, `NNNN-<slug>.md`, template embedded in the skill (title, status, context, decision, consequences)
- [ ] T024 [P] [US1] Write `plugins/conventions/skills/release/SKILL.md`: release PR `integrationBranch → productionBranch`, changelog grouped by `apps` keys, migration directories found by glob `**/migrations/`, `disable-model-invocation: true`
- [ ] T025 [P] [US1] Write `plugins/conventions/skills/deps-audit/SKILL.md`: package-manager aware audit command and override location (`pnpm-workspace.yaml#overrides`, `package.json#overrides`, `package.json#resolutions`), exact-pin bump first, `disable-model-invocation: true`
- [ ] T026 [P] [US1] Write `plugins/conventions/agents/ci-triage.md` (haiku; Bash, Read, Grep, Glob): discover `.github/workflows/*.yml`, map jobs to `apps`, report failing job / command / error / suspected file:line
- [ ] T027 [P] [US1] Write `plugins/conventions/agents/rules-reviewer.md` (sonnet; Read, Grep, Glob, Bash): review a diff against the target's `.claude/rules/**`; ring paths taken from the target's `architecture.md`; ranked findings
- [ ] T028 [P] [US1] Write `plugins/conventions/agents/test-writer.md` (sonnet): test layout from `architecture.md` table, verify with `/conventions:verify-app`
- [ ] T029 [P] [US1] Write `plugins/conventions/agents/repo-explorer.md` (haiku; `memory: project`): app/package list from `conventions.json#apps` and the workspace manifest
- [ ] T030 [P] [US1] Write `profiles/conventions.json` (`{ "description": …, "plugins": ["conventions@claude-conventions"], "skills": [] }`) and verify `ccprofile inspect conventions` reads it once symlinked into `~/.claude/profiles/`
- [ ] T031 [US1] Run `shellcheck` on all hooks, `tests/run.sh` (all US1 assertions green), `claude plugin validate plugins/conventions`; grep `plugins/` for bsk identifiers → zero hits

**Checkpoint**: quickstart §2 passes on the `pnpm-biome` fixture.

---

## Phase 4: User Story 2 — Port the rules into a new repository (Priority: P2)

**Goal**: `/conventions:port-claude-config` discovers, proposes, waits, then writes the project config from templates.

**Independent Test**: quickstart §3 on the `pnpm-biome` fixture — stops at the mapping table; after confirmation produces the listed files; every command in `commands.md` runs.

- [ ] T032 [P] [US2] Write `plugins/conventions/skills/port-claude-config/scripts/discover.sh`: prints one JSON with `packageManager`, `formatter`, `lockfiles[]`, `workspaces[]` (from `pnpm-workspace.yaml` / `package.json#workspaces`), `apps{}` guess (workspace dirs with a `package.json`), `defaultBranch`, `branches[]`, `ciWorkflows[]` with each job's `run:` lines, `existingClaude{}` (paths under `.claude/`, `CLAUDE.md`), `hasGitignoreClaude`; shellcheck-clean; `jq` only
- [ ] T033 [P] [US2] Write templates in `plugins/conventions/skills/port-claude-config/templates/`: `CLAUDE.md`, `rules/workflow.md`, `rules/architecture.md` (includes the "Test layout" table skeleton), `rules/knowledge.md`, `rules/pitfalls.md`, `rules/commands.md` (per-app sheet skeleton), `settings.json` (permissions from `{{PERMISSIONS}}`, deny force-push, `"enabledPlugins": {}`, no hooks), `conventions.json`, `gitignore` — generic sections wrapped in `<!-- conventions:begin <id> -->`/`<!-- conventions:end <id> -->` per `contracts/templates.md`; placeholders exactly the list in that contract; wording ported from the reference rules minus bsk specifics
- [ ] T034 [US2] Write `plugins/conventions/skills/port-claude-config/scripts/render.sh <template> <conventions.json> [--app-table <file>] [--permissions <file>]`: substitutes every `{{PLACEHOLDER}}`, fails (exit 1, names the placeholder) if any remains; shellcheck-clean
- [ ] T035 [US2] Write `plugins/conventions/skills/port-claude-config/SKILL.md`: step 1 run `discover.sh` and read the reference list; step 2 print the mapping table (template → keep/adapt/drop → target path, plus duplicates found in existing `.claude/hooks/`) and the open questions (integration branch, size cap, deploy branches, `.claude/` committed?) then STOP; step 3 on confirmation write `conventions.json`, rendered templates, `settings.json` permissions derived from commands actually run, one `commands.md` per app whose commands are quoted from CI or run once (record the run output), `.gitignore` negations; refuse to write unverified commands; never commit; frontmatter `argument-hint: "[--refresh]"`
- [ ] T036 [US2] Add `tests/run.sh` assertions for `discover.sh` on all three fixtures (expected `packageManager`, `formatter`, `apps`) and for `render.sh` (all placeholders resolved; unresolved placeholder → exit 1)
- [ ] T037 [US2] Walk quickstart §3 on a copy of `pnpm-biome` in a Claude Code session; fix the skill until the produced files match `data-model.md` "Target repo config" and every `commands.md` command succeeds

**Checkpoint**: a fresh fixture is fully ported in one confirmed run.

---

## Phase 5: User Story 3 — Update once, propagate everywhere (Priority: P3)

**Goal**: plugin updates propagate without re-port; `--refresh` updates template-owned sections only.

**Independent Test**: quickstart §4.

- [ ] T038 [US3] Write `plugins/conventions/skills/port-claude-config/scripts/refresh.sh <target-root>`: for each template with sentinels, replace the body between matching `conventions:begin/end <id>` pairs in the target file with the rendered body; append missing sections with a notice line; skip files without sentinels; never touch `conventions.json`, `settings.json`, `rules/<app>/`; prints the list of changed files; shellcheck-clean
- [ ] T039 [US3] Add `--refresh` branch to `plugins/conventions/skills/port-claude-config/SKILL.md`: runs `refresh.sh`, shows `git diff --stat`, no questions
- [ ] T040 [US3] Add `tests/run.sh` assertions for `refresh.sh`: hand-edited text outside sentinels preserved byte-for-byte, `pitfalls.md` entries preserved, a changed template line lands inside the section, `rules/api/commands.md` untouched (`cmp`)
- [ ] T041 [US3] Document the update path in `README.md` §Update (`git pull` in the clone is not enough: `claude plugin update conventions@claude-conventions`; `ccprofile sync` for profile drift; `/conventions:port-claude-config --refresh` for templates) and verify quickstart §4 end-to-end

---

## Phase 6: User Story 4 — Hooks resolve their values without configuration (Priority: P3)

**Goal**: npm + Prettier and no-conventions repos behave correctly with zero or minimal config.

**Independent Test**: quickstart §5 / `tests/run.sh` on the two extra fixtures.

- [ ] T042 [P] [US4] Write `tests/fixtures/npm-prettier/`: `package.json`, `package-lock.json` (minimal valid), `.prettierrc`, `src/index.ts` unformatted, `.claude/conventions.json` with only `integrationBranch: "develop"`
- [ ] T043 [P] [US4] Write `tests/fixtures/no-conventions/`: `package.json`, `pnpm-lock.yaml`, no `.claude/`
- [ ] T044 [US4] Add `tests/run.sh` assertions (npm-prettier): `npm install lodash` → 2 with `--save-exact` in stderr; `npm install --save-exact lodash` → 0; edit `src/index.ts` → formatted by Prettier; `pr-size` default cap 400/15 applies; `guard-git` uses `origin/HEAD` fallback `main` as production
- [ ] T045 [US4] Add `tests/run.sh` assertions (no-conventions): `git push --force` → 0 with stderr `conventions.json missing — skipped`; `gh pr create --base main` → 0 with the same warning; `pnpm add lodash` → 2 (detection needs no file); `branch-info` prints the branch and a hint to run `/conventions:port-claude-config`; fixture with both `pnpm-lock.yaml` and `package-lock.json` added on the fly → `deps-exact` warns and exits 0
- [ ] T046 [US4] Make T044–T045 green in `lib.sh` / hooks without regressing Phase 3 assertions

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T047 [P] Write `schema/conventions.schema.json` (JSON Schema draft 2020-12) matching `data-model.md` "Conventions file" (types, enums, required `integrationBranch`, defaults in `description`); reference it from `templates/conventions.json#$schema`
- [ ] T048 [P] Write `README.md`: what it is, one-time machine setup (`claude plugin marketplace add Azurioh/claude-conventions`, profile symlink), per-project setup (`ccprofile apply conventions`, `/conventions:port-claude-config`), value resolution table, hook behaviour summary, skills/agents list with namespaced names, `verifier` prerequisite, update path, development (`tests/run.sh`, `shellcheck`, `claude plugin validate`)
- [ ] T049 Bump nothing; verify `plugin.json` and `marketplace.json` versions agree (`0.1.0`) and `claude plugin validate plugins/conventions` passes
- [ ] T050 Run the full gate from quickstart §1 and §2–§5 on the fixtures; record outputs in the PR body; grep `plugins/ README.md` for bsk identifiers → zero hits
- [ ] T051 Update `specs/001-claude-conventions-plugin/quickstart.md` with any deviation found during T050 and mark the spec `Status: Implemented`

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → Phase 3 (US1, MVP) → Phases 4–6 in any order (US2 depends on Phase 2 only; US3 depends on US2 templates; US4 depends on US1 hooks) → Phase 7.
- Within US1: tests T010–T014 before hooks T015–T019; hooks T016–T019 parallel after T015 (shared `lib.sh` finalised there); skills/agents T020–T030 parallel with hooks.
- Within US2: T032 ∥ T033 → T034 → T035 → T036 → T037.
- Within US3: T038 → T039 ∥ T040 → T041.
- Within US4: T042 ∥ T043 → T044 ∥ T045 → T046.

## Parallel Execution Examples

- US1: one implementer on hooks (T015→T016–T019), one on skills (T020–T025), one on agents + profile (T026–T030).
- US2: T032 and T033 in parallel, then serial.
- US4: fixtures T042/T043 in parallel.

## Implementation Strategy

MVP = Phases 1–3: installable plugin with working hooks, skills and agents on a pnpm+Biome repo. Then US2 (port) makes a fresh repo fully tooled; US3/US4 harden update and detection; Phase 7 ships README/schema/CI.
