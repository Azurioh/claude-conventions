# Research: Claude Conventions Plugin

Sources: Claude Code docs (`plugins.md`, `plugins-reference.md`, `plugin-marketplaces.md`,
`hooks.md` on code.claude.com, fetched 2026-09-17), local machine state
(`~/.claude/plugins/known_marketplaces.json`, `bsk-apps/.claude/settings.local.json`),
and the reference implementation `bsk-apps/.claude` (branch `docs/claude-config-spec`).

## R1 — Marketplace and plugin format

- **Decision**: repo root holds `.claude-plugin/marketplace.json` (`name: "claude-conventions"`,
  `owner`, `plugins: [{ name: "conventions", source: "./plugins/conventions", version }]`);
  the plugin holds `plugins/conventions/.claude-plugin/plugin.json` (`name`, `version`,
  `description`) plus conventional dirs `hooks/hooks.json`, `skills/<n>/SKILL.md`, `agents/<n>.md`.
- **Rationale**: matches the documented layout; a GitHub-hosted marketplace registers with
  `claude plugin marketplace add Azurioh/claude-conventions` (recorded as
  `{source: github, repo}` in `known_marketplaces.json`, keyed by the manifest `name`).
  Install id is therefore `conventions@claude-conventions`; `enabledPlugins` stores
  `"conventions@claude-conventions": true` (confirmed from existing local settings).
- **Alternatives**: plugin as its own repo without marketplace (needs a marketplace anyway to
  install by name); git subtree of `.claude/` (no central update path). Rejected.

## R2 — What a plugin can and cannot ship

- **Decision**: hooks, skills, agents in the plugin; rules and `CLAUDE.md` as templates copied
  by the `port-claude-config` skill. Templates live inside the skill directory
  (`skills/port-claude-config/templates/`) so the skill resolves them relative to itself.
- **Rationale**: docs state a plugin's `CLAUDE.md` is not loaded as project context and there
  is no rules mechanism in plugins.
- **Consequence**: plugin skills are namespaced `/conventions:<skill>`; rules and agents that
  mention a skill must use the namespaced form.

## R3 — Hook protocol

- **Decision**: keep the reference behaviour — read stdin JSON with `jq`
  (`.tool_name`, `.tool_input.command`, `.tool_input.file_path`, `.cwd`), deny with exit 2 and
  a one-line stderr reason, never block on formatter/session hooks (exit 0). SessionStart
  context is emitted on stdout. Commands in `hooks.json` use `${CLAUDE_PLUGIN_ROOT}/hooks/<x>.sh`;
  the project directory comes from `$CLAUDE_PROJECT_DIR` (fallback `.cwd`).
- **Rationale**: exit-2 denial is documented and already proven by `test-hooks.sh`; JSON
  `permissionDecision` output adds nothing for a deny-only hook.
- **Events/matchers**: `PreToolUse` matcher `Bash`; `PostToolUse` matcher `Edit|Write`;
  `SessionStart` no matcher. Timeouts 10/10/20/30/5 s as in the reference.

## R4 — Per-repo values (FR-003/FR-004)

- **Decision**: `.claude/conventions.json` in the consuming repo (contract in
  `contracts/conventions-json.md`). `lib.sh` exposes `conv_get <jq-path> <default>` and
  detectors: package manager from lockfile (`pnpm-lock.yaml`→pnpm, `package-lock.json`→npm,
  `yarn.lock`→yarn, `bun.lockb`/`bun.lock`→bun; two lockfiles → unset unless overridden),
  formatter from `biome.json`/`biome.jsonc`→biome, `.prettierrc*`/`prettier.config.*`/
  `"prettier"` key in `package.json`→prettier; none → no-op. Size cap default 400/15,
  default exclude list `[**/pnpm-lock.yaml, **/package-lock.json, **/yarn.lock,
  **/migrations/**, **/components/ui/**]`, label `large-pr`.
- **Rationale**: user decision (auto-detect + override). Only `integrationBranch` is mandatory;
  missing file → hooks needing it print `conventions: .claude/conventions.json missing —
  <hook> skipped` on stderr and exit 0.
- **Alternatives rejected**: env vars in `settings.json` (mixes with permissions), full
  explicit file (drifts from the repo).

## R5 — Generalising the reference hooks

| Reference | Plugin | Parameterised by |
|---|---|---|
| `guard-git.sh` (blocks `git push --force`, bare `git stash`/`pop`, commits/pushes on `main`/`demo`, `gh pr create --base` ≠ demo) | `guard-git.sh` | `integrationBranch`, `productionBranch` (default: `git symbolic-ref refs/remotes/origin/HEAD`, fallback `main`) |
| `pr-size.sh` (400/15, excludes, `--label large-pr`, release exception) | `pr-size.sh` | `prSize.{lines,files,exclude,label}`, release exception = base `productionBranch` head `integrationBranch` |
| `pnpm-exact.sh` (`pnpm add` without `-E`) | `deps-exact.sh` | package manager: pnpm `-E`/`--save-exact`, npm `--save-exact`/`-E`, yarn `--exact`/`-E`, bun `--exact`/`-E` |
| `biome-format.sh` (`pnpm exec biome check --write`) | `format.sh` | formatter × package manager: `<pm> exec biome check --write <file>` / `<pm> exec prettier --write <file>`; extension list unchanged |
| `branch-info.sh` (warns on `main`/`demo`) | `branch-info.sh` | protected = `{productionBranch, integrationBranch}` |
| `test-hooks.sh` | `tests/run.sh` | runs the same assertions per fixture |

## R6 — Generalising skills and agents

- `pr`: bases from `conventions.json`; size cap/excludes from the same file; "logical group"
  split guidance kept; app names dropped.
- `verify-app`: apps from `conventions.json#apps`; the CI sequence of an app is read from
  `.claude/rules/<app>/commands.md` (single-app repo: `.claude/rules/commands.md`). Forks
  into the user's global `verifier` agent (documented prerequisite).
- `test-gaps`: layer → test-directory mapping is read from the project's
  `.claude/rules/architecture.md` "Test layout" table (template-owned section) instead of
  being hardcoded.
- `adr`: unchanged except the path is `docs/adr/` by default, overridable by
  `conventions.json#adrDir`.
- `release`: bases from `conventions.json`; changelog grouped by `apps` keys; migration
  paths discovered by glob (`**/migrations/`) instead of hardcoded.
- `deps-audit`: package-manager aware (`pnpm audit`/`npm audit`, overrides in
  `pnpm-workspace.yaml` vs `package.json#overrides`/`resolutions`).
- `ci-triage`: workflow files discovered under `.github/workflows/`; job→app mapping from
  `apps`.
- `rules-reviewer`: reads `.claude/rules/**` of the target; ring paths from the project's
  `architecture.md` instead of bsk paths.
- `test-writer`: test layout from `architecture.md` table; verify via
  `/conventions:verify-app`.
- `repo-explorer`: app/package list from `conventions.json#apps` + workspace file; keeps
  `memory: project`.
- Skipped (app-specific): `bot-dev`, `hub-dev`, `cms-dev`, `web-dev`, `bot-module`,
  `hub-procedure`, `cms-collection`, `rules/{discord-bot,hub,cms,website,packages}`.

## R7 — Refresh mode (FR-010)

- **Decision**: templates wrap generic content in sentinel comments
  `<!-- conventions:begin <section-id> -->` … `<!-- conventions:end <section-id> -->`.
  Refresh replaces only the text between matching sentinels; content outside (app table,
  pitfalls entries, hand-written sections) and files without sentinels are untouched. A
  sentinel present in the template but absent in the file is appended at the end with a
  notice.
- **Rationale**: byte-identical guarantee for per-app files (SC-005) without a merge engine.

## R8 — Test harness

- **Decision**: `tests/run.sh` (bash, shellcheck-clean) copies each `tests/fixtures/<name>/`
  into a temp dir, `git init`s it with a `main` branch and an integration branch, then feeds
  hand-built stdin JSON to every hook and asserts exit code + stderr substring. Fixtures:
  `pnpm-biome` (conventions file, `pnpm-lock.yaml`, `biome.json`), `npm-prettier`
  (`package-lock.json`, `.prettierrc`), `no-conventions` (lockfile only). `shellcheck` over
  `hooks/*.sh tests/*.sh` and `claude plugin validate plugins/conventions` complete the
  local gate; CI runs shellcheck + `tests/run.sh` (no `claude` CLI in CI).
- **Alternatives rejected**: bats (extra dependency for ~15 assertions).

## R9 — ccprofile integration

- **Decision**: ship `profiles/conventions.json` (`{ "plugins": ["conventions@claude-conventions"], "skills": [] }`)
  and document `ln -s <clone>/profiles/conventions.json ~/.claude/profiles/conventions.json`.
  ccprofile does not register marketplaces — README states the one-time
  `claude plugin marketplace add Azurioh/claude-conventions`.
- **Rationale**: ccprofile writes `enabledPlugins` into `settings.local.json` when
  `settings.json` owns the key (patched 2026-09-17), which is what the port skill seeds.
