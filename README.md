# claude-conventions

A Claude Code plugin marketplace with one plugin, `conventions`: git guardrails
(no force-push, no direct commit on the production or integration branch, no
bare stash), exact-pinned dependencies, a PR size cap, formatter-on-save, a
branch banner, plus generic skills and agents. Every hook reads its values
from the repository's `.claude/conventions.json`; a port skill writes the rule
templates (`CLAUDE.md`, `.claude/rules/*`) into a repository once and refreshes
them later without touching what the project wrote by hand.

Why a plugin: every repository used to copy the same hooks, skills and rules by
hand, and the copies drifted. Here the reusable layer is installed once per
machine, enabled per repository, and updated centrally; only the values that
differ between repositories (branches, package manager, formatter, size cap,
app list) live in the repository.

## Install

Once per machine. Prerequisites: Claude Code CLI, `jq`, `git`, `gh`, and the
personal `ccprofile` script at `~/.claude/bin/ccprofile` (per-project
plugin/skill profiles; optional, see below) for the per-project step.

```bash
claude plugin marketplace add Azurioh/claude-conventions
git clone https://github.com/Azurioh/claude-conventions ~/Repositories/claude-conventions
ln -s ~/Repositories/claude-conventions/profiles/conventions.json ~/.claude/profiles/conventions.json
```

The marketplace registration is what `claude plugin install` and
`claude plugin update` resolve `conventions@claude-conventions` against. The
clone is only needed for the profile symlink (and for development); the plugin
itself runs from Claude Code's plugin cache. Without `ccprofile`, enable the
plugin by hand: `claude plugin install conventions@claude-conventions`, then
`"enabledPlugins": { "conventions@claude-conventions": true }` in the
repository's `.claude/settings.local.json`.

## Per-project setup

Run in the repository root, once.

| Step | Command | Result |
|---|---|---|
| 1. enable the plugin | `ccprofile apply conventions` | `enabledPlugins["conventions@claude-conventions"] = true` — written to `.claude/settings.local.json` when `.claude/settings.json` already owns the key (the port step seeds it that way), else to `.claude/settings.json` |
| 2. start a session | `claude` | the branch banner appears; hooks warn `conventions/<hook>: .claude/conventions.json missing — skipped` until step 3 |
| 3. port the rules | `/conventions:port-claude-config` | discovery → mapping table + open questions → **stops** → after your answers writes `CLAUDE.md`, `.claude/rules/{workflow,architecture,knowledge,pitfalls}.md`, one `commands.md` per app, `.claude/settings.json`, `.claude/conventions.json`, `.gitignore` negations |
| 4. app rules | `/conventions:app-rules <app>` (or `all`) | analysis of the app's code → preview of `.claude/rules/<app>/architecture.md`, optional `conventions.md`, `.claude/agents/<app>-dev.md` and the app's **Test layout** rows → **stops** → writes after confirmation (single-app: `.claude/rules/app.md`, `.claude/agents/app-dev.md`) |
| 5. commit | `git add CLAUDE.md .claude .gitignore && git commit` | `.claude/settings.local.json` stays ignored |

A repository can stay at step 2 (guardrails that need no repository value —
bare `git stash`, exact-pin — already work); the branch-related checks skip
until `.claude/conventions.json` carries `integrationBranch`.
Step 3 writes the generic rules (the same for every repository); step 4 writes
what only this app's code can tell — rings, composition root, forbidden
imports, test prerequisites — and a per-app implementer agent.

Skills that fork into a verifier (`/conventions:verify-app`,
`/conventions:test-gaps`) need a `verifier` agent in `~/.claude/agents/` — a
personal agent that runs commands and triages failures. It is not shipped
here.

## Bootstrap a repository with Claude

Claude in a fresh repository has not read this README. Open a session in the
repository root and paste the prompt below; it runs the per-project setup end
to end and stops at every confirmation point.

```text
Bootstrap this repository with the claude-conventions plugin. Do not commit anything.

1. Register the marketplace unless `claude plugin marketplace list` already shows it:
   `claude plugin marketplace add Azurioh/claude-conventions`. Then run
   `ccprofile apply conventions` and report the `enabledPlugins` entry it wrote and
   in which file (`.claude/settings.local.json` or `.claude/settings.json`).
   Plugins load at session start: if `/conventions:port-claude-config` is not
   available yet, tell me to restart the session and stop here; I will paste this
   prompt again.
2. Run `/conventions:port-claude-config`. Stop at the mapping table, ask me the open
   questions, and write only after I confirm.
3. For each app listed in `.claude/conventions.json#apps` (or the single app when the
   key is absent), run `/conventions:app-rules <app>`. Stop at the preview and write
   only after I confirm.
4. Run `/conventions:test-gaps all` and report the result. End with the list of files
   you created and the commands you verified.
```

| After step | You have |
|---|---|
| 1 | the plugin enabled for this repository: hooks, `/conventions:*` skills and `conventions:*` agents on the next session |
| 2 | `CLAUDE.md`, `.claude/rules/{workflow,architecture,knowledge,pitfalls}.md`, one `commands.md` per app, `.claude/settings.json`, `.claude/conventions.json`, `.gitignore` negations |
| 3 | per app: `.claude/rules/<app>/architecture.md`, `conventions.md` when the code has recurring patterns, `.claude/agents/<app>-dev.md`, the app's rows in the **Test layout** table |
| 4 | the list of changed source files without a test, and a working tree to review with `git diff` and commit |

## How hooks resolve values

`.claude/conventions.json` (schema: [`schema/conventions.schema.json`](schema/conventions.schema.json)).
Only `integrationBranch` is required; every other key overrides a detected or
default value. Unknown keys are ignored.

| Key | Type | Detection when absent | Default |
|---|---|---|---|
| `integrationBranch` | string | — | none: hooks needing it warn and skip |
| `productionBranch` | string | branch `origin/HEAD` points to | `main` |
| `packageManager` | `pnpm` \| `npm` \| `yarn` \| `bun` | lockfile: `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lock`/`bun.lockb` | unset when two lockfiles coexist (dependency guard warns, passes) |
| `formatter` | `biome` \| `prettier` \| `none` | `biome.json`/`biome.jsonc` → biome; `.prettierrc*`, `prettier.config.*`, `"prettier"` key in `package.json` → prettier | `none` |
| `prSize.lines` | integer | — | `400` |
| `prSize.files` | integer | — | `15` |
| `prSize.exclude` | string[] (globs) | — | `**/pnpm-lock.yaml`, `**/package-lock.json`, `**/yarn.lock`, `**/migrations/**`, `**/components/ui/**` (an override replaces the whole list) |
| `prSize.label` | string | — | `large-pr` |
| `apps` | object `name → path` | — | absent = single-app repository |
| `adrDir` | string | — | `docs/adr` |
| `deployNote` | string | — | empty; written by the port skill, rendered into the rules, not read by hooks |

Hook behaviour (deny = exit 2 + one stderr line `conventions/<hook>: <reason>`;
outside a git repository every hook exits 0 silently):

| Hook | Event | Refuses | Passes / notes |
|---|---|---|---|
| `guard-git` | PreToolUse `Bash` | force push or direct push to the production or integration branch; `git commit` / `git push` while checked out on one of them; `gh pr create` without `--base` or with `--base <production>`; bare `git stash`, `git stash pop` | release pair `--base <production> --head <integration>`; force push to a feature branch; `git stash push -m …` / `apply` |
| `deps-exact` | PreToolUse `Bash` | `add`/`install` of a package without the exact flag for the detected manager (pnpm `-E`, npm `--save-exact`, yarn/bun `--exact`) | `<pkg>@<x.y.z>`; commands of another package manager; undetected manager → warning |
| `pr-size` | PreToolUse `Bash` | `gh pr create` whose diff against `--base` exceeds `prSize.lines` or `prSize.files` after `prSize.exclude` | `--label <prSize.label>`; the release pair; missing `--base` (guard-git already refuses it) |
| `format` | PostToolUse `Edit\|Write` | nothing (never blocks) | runs `biome check --write` / `prettier --write` on `.ts .tsx .js .mjs .cjs .json .css` via `node_modules/.bin/<formatter>` or PATH; silent when not installed; one stderr line when the formatter fails |
| `branch-info` | SessionStart | nothing | prints `git branch:`, `upstream:`, a `WARNING:` when on a protected branch, and a `conventions:` line when the file is missing, not JSON, lacks `integrationBranch`, or has `integrationBranch == productionBranch` |

## Skills and agents

Skills (invoke as `/conventions:<name>`):

| Skill | Purpose | Reads |
|---|---|---|
| `pr` | open the PR the repo way (conventional title, what/why/verification body, base = integration branch); `--stack` splits an oversize diff into a GitHub-native stack | `integrationBranch`, `productionBranch`, `prSize.*`, `apps` |
| `verify-app <app\|all>` | run one app's CI sequence from `.claude/rules/<app>/commands.md` (single-app: `.claude/rules/commands.md`) and triage failures; forks into `verifier` | `apps` |
| `test-gaps <app\|all>` | list changed source files without a matching test, using the **Test layout** table of `.claude/rules/architecture.md`; forks into `verifier` | `integrationBranch`, `apps` |
| `adr <title>` | write the next `NNNN-<slug>.md` decision record | `adrDir`, `apps` |
| `release` | prepare the integration → production PR (changelog by app, migrations, env vars); never merges; user-invoked only | `integrationBranch`, `productionBranch`, `apps` |
| `deps-audit` | run the dependency audit with the repo's package manager and fix advisories (exact-pinned bumps, transitive pins); user-invoked only | `packageManager` |
| `port-claude-config [--refresh]` | port the rule templates into the repository (see Per-project setup); `--refresh` re-renders the template-owned sections only (see Update) | everything |
| `app-rules <app\|all>` | analyse one app's code and write its project-specific rules — `.claude/rules/<app>/architecture.md`, optional `conventions.md`, `.claude/agents/<app>-dev.md`, the app's **Test layout** rows — after a preview and confirmation; single-app: `.claude/rules/app.md`, `.claude/agents/app-dev.md` | `apps`, `adrDir` |

Agents (available as `conventions:<name>` subagents):

| Agent | Model | Purpose |
|---|---|---|
| `ci-triage` | haiku | read-only triage of a red GitHub Actions run: job, app, command, exact error, suspected cause |
| `rules-reviewer` | sonnet | review a diff against the repository's `.claude/rules/**`; ranked findings, no praise |
| `test-writer` | sonnet | write the tests `/conventions:test-gaps` reported as missing, in the app's harness; verifies through `/conventions:verify-app` |
| `repo-explorer` | haiku | cheap read-only exploration of the repository with project memory |

## Update

Three things can go stale in a consuming repository, and each has its own
update path. A `git pull` in the clone of this repository updates none of
them: Claude Code runs the plugin from its own cache, and the rule files
live inside each repository.

| What changed in `claude-conventions` | Command in the consuming repository | Effect |
|---|---|---|
| a hook, a skill or an agent under `plugins/conventions/` | `claude plugin update conventions@claude-conventions` | new behaviour on the next session, no file changes in the repository. Only a **new version** is installed: bump `version` in both `.claude-plugin/marketplace.json` and `plugins/conventions/.claude-plugin/plugin.json` before pushing, or the update reports "already at the latest version" |
| the profile (`profiles/conventions.json`) | `ccprofile sync` (`ccprofile verify` shows the drift first) | `.claude/settings.local.json` reconciled with the profile |
| a rule template under `skills/port-claude-config/templates/` | `/conventions:port-claude-config --refresh` | the template-owned sections of the rule files rewritten; review with `git diff`, then commit |

`--refresh` asks nothing and runs `refresh.sh <repo-root>`: for each template that
carries `<!-- conventions:begin <id> -->` … `<!-- conventions:end <id> -->`
sections and whose target file exists, it renders the sections from the current
`.claude/conventions.json` and replaces the body between the same-id sentinels in
the file. Everything outside the sentinels stays byte-identical. A section the
template gained since the port is appended at the end of the file after a one-line
`<!-- conventions:refresh — … -->` notice; move it where it belongs. The script
prints the changed files and exits 0 even when nothing changed.

Refresh never touches: `.claude/conventions.json`, `.claude/settings.json`,
`.gitignore`, every `commands.md` (per-app sheets under `.claude/rules/<app>/`
and the single-app `.claude/rules/commands.md`), the `pitfalls.md` entries, the
app table in `CLAUDE.md`, the **Test layout** table in `architecture.md`, any
hand-written section, and any file without a sentinel (a `CLAUDE.md` kept as is
during the port). It exits 1 without writing when `.claude/conventions.json` is
missing, when a section needs a value the file lacks (the placeholder is named),
or when a sentinel section in a target file has lost its end marker.

## Development

```bash
shellcheck plugins/conventions/hooks/*.sh plugins/conventions/skills/port-claude-config/scripts/*.sh tests/*.sh
tests/run.sh                                  # "OK: N assertions"; SKIP lines when biome/prettier are not resolvable
claude plugin validate plugins/conventions    # plugin manifest
claude plugin validate .                      # marketplace manifest
```

CI (`.github/workflows/ci.yml`) runs shellcheck and `tests/run.sh` on Ubuntu with
`jq` only — no Node, no Claude CLI.

Layout:

| Path | Content |
|---|---|
| `.claude-plugin/marketplace.json` | marketplace `claude-conventions`, one plugin entry |
| `plugins/conventions/.claude-plugin/plugin.json` | plugin manifest; version must match the marketplace entry |
| `plugins/conventions/hooks/` | `hooks.json`, `lib.sh` (segment splitting, value lookup, detectors), one script per hook |
| `plugins/conventions/skills/<name>/SKILL.md` | skills; `port-claude-config/` also holds `scripts/{discover,render,refresh}.sh` and `templates/` |
| `plugins/conventions/agents/<name>.md` | agents |
| `profiles/conventions.json` | ccprofile profile |
| `schema/conventions.schema.json` | JSON Schema (draft 2020-12) of `.claude/conventions.json` |
| `tests/run.sh` | copies each fixture to a temp dir, `git init`s it, feeds hand-built hook events, asserts exit code, stderr, stdout and file contents; also covers `discover.sh`, `render.sh`, `refresh.sh` |
| `tests/fixtures/pnpm-biome` | `pnpm-lock.yaml`, `biome.json`, `apps/api` workspace, conventions with `apps` |
| `tests/fixtures/npm-prettier` | `package-lock.json`, `.prettierrc`, conventions with `integrationBranch` only |
| `tests/fixtures/no-conventions` | `pnpm-lock.yaml` only, no `.claude/` |

Releasing a change under `plugins/conventions/`: bump `version` in
`plugins/conventions/.claude-plugin/plugin.json` **and** in the plugin entry of
`.claude-plugin/marketplace.json` (same value), then push. `claude plugin update`
only installs a new version — with an unchanged version it reports "already at
the latest version" and consuming repositories keep the old copy.

Every script is bash with `set -euo pipefail` (`format.sh`: `set -uo pipefail`,
it must never fail) and stays shellcheck-clean; `.shellcheckrc` resolves
`# shellcheck source=lib.sh` from any working directory. JSON files are
2-space indented.
