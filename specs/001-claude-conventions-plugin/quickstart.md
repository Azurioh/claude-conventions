# Quickstart: validating the Claude Conventions Plugin

Prerequisites: `jq`, `shellcheck`, `git`, `gh`, Claude Code CLI, `~/.claude/bin/ccprofile`.
Run every fixture step in a temporary copy, never in a real repository.

## 1. Repository gate (run in the clone)

```bash
shellcheck plugins/conventions/hooks/*.sh plugins/conventions/skills/port-claude-config/scripts/*.sh tests/*.sh
tests/run.sh                       # all fixtures, all hooks → "OK: N assertions" (SKIP lines when biome/prettier are not installed)
claude plugin validate plugins/conventions
claude plugin validate .           # marketplace manifest
```

## 2. Install into a fixture (User Story 1 / SC-001)

```bash
claude plugin marketplace add Azurioh/claude-conventions   # once per machine (published clone)
ln -s "$PWD/profiles/conventions.json" ~/.claude/profiles/conventions.json
cp -R tests/fixtures/pnpm-biome /tmp/fx && cd /tmp/fx && git init -q -b main && git switch -c develop
ccprofile apply conventions && cat .claude/settings.json          # expect "conventions@claude-conventions": true
```

`develop` is the fixture's `integrationBranch`. On a repository without
`.claude/settings.json`, `ccprofile apply` writes `enabledPlugins` into
`.claude/settings.json`; it switches to `.claude/settings.local.json` only when
`settings.json` already owns the key (which is how the port step seeds it).

Unpublished clone: register it from inside the fixture instead, so nothing is
declared at user scope —
`claude plugin marketplace add <clone> --scope local && claude plugin install conventions@claude-conventions --scope local`
(the install lands in `.claude/settings.local.json`; `ccprofile apply` is then
redundant). Clean up with `claude plugin uninstall conventions@claude-conventions --scope local`
and `claude plugin marketplace remove claude-conventions`; an orphan copy stays
under `~/.claude/plugins/cache/claude-conventions/` and can be deleted.

Start a Claude Code session in `/tmp/fx`; expect the branch banner, then:
`git push --force origin develop` → refused; `pnpm add lodash` → refused with the `-E` form
suggested; `/conventions:pr` listed in skills (`release` and `deps-audit` are hidden from the
model by `disable-model-invocation`). Headless variant: `claude -p '<ask for the banner and
the command>' --allowedTools "Bash(git push*)"`.

## 3. Port the rules (User Story 2 / SC-002)

In an **interactive** session: `/conventions:port-claude-config`. Expect the mapping table and
the open questions, no file written. Answer; expect `CLAUDE.md`, `.claude/rules/*.md`,
`.claude/rules/<app>/commands.md`, `.claude/settings.json`, `.claude/conventions.json`,
`.gitignore`. Then run every command in the produced `commands.md` files — all must succeed.
A nested `claude -p` (started from another Claude Code session) shows the mapping and stops,
but cannot write under `.claude/` (auto-denied as a sensitive path) nor run the discovery
script or the package manager; use a normal terminal for the second half, or replay step 3
by hand with `scripts/discover.sh`, `scripts/render.sh <template> .claude/conventions.json`
and the `commands.md` sequence.

## 4. Update propagation and refresh (User Story 3 / SC-004, SC-005)

`claude plugin update` installs a **new version only**: with the same `version`, it reports
"already at the latest version" and the cached copy is not refreshed. Change a stderr message
in `plugins/conventions/hooks/guard-git.sh`, bump `version` in
`plugins/conventions/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`,
commit, push, then in the fixture
`claude plugin marketplace update claude-conventions && claude plugin update conventions@claude-conventions`
(same `--scope` as the install); re-run the refused command in the fixture — new message,
`git status` in the fixture clean. With a directory-source marketplace (the local clone) the
hooks run straight from the clone, so the new message shows even before the update; the
version bump is what refreshes `~/.claude/plugins/cache/`.

Refresh: edit a template line (or point `CONVENTIONS_TEMPLATES_DIR` at an edited copy), run
`/conventions:port-claude-config --refresh` (or `scripts/refresh.sh <fixture>` directly);
`git diff --stat` shows only the generic rule file; `rules/<app>/` untouched.

## 5. Value resolution (User Story 4 / SC-003)

`tests/run.sh` covers pnpm+biome, npm+prettier and no-conventions; to check by hand, copy
`tests/fixtures/npm-prettier` and repeat step 2 — `npm install lodash` refused, `--save-exact`
suggested; edit a `.ts` file → Prettier runs when `node_modules/.bin/prettier` (or `prettier`
on PATH) exists, silently skipped otherwise.
