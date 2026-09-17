---
name: port-claude-config
description: Ports the conventions rule set into the current repository — discovers the stack, CI sequences, branches and existing Claude config, shows a mapping table plus the open questions, waits for confirmation, then writes CLAUDE.md, .claude/rules/*, one commands.md per app, .claude/settings.json, .claude/conventions.json and the .gitignore negations. Use when a repo has just installed the plugin, when hooks warn that .claude/conventions.json is missing, when the user says "port the rules", "set up the conventions", "bootstrap the Claude config", or with --refresh to re-apply template changes.
argument-hint: "[--refresh]"
---
Never commit. Never write a file before the user has confirmed step 2. Every path below is relative to the repo root (`git rev-parse --show-toplevel`).

```bash
SKILL="${CLAUDE_PLUGIN_ROOT}/skills/port-claude-config"
```

`$ARGUMENTS` contains `--refresh` → skip to **Refresh** at the end.

## Step 1 — discover

1. `"$SKILL/scripts/discover.sh" > /tmp/discover.json && cat /tmp/discover.json` — one JSON object: `packageManager`, `formatter`, `lockfiles`, `workspaces`, `apps` (guess: workspace members with a `package.json`, name = dir basename), `packageScripts` (per package dir), `defaultBranch`, `branches`, `ciParser` (`yq` / `awk` / `none`), `ciWorkflows[].jobs[].run[]` (every `run:` line per job, verbatim), `existingClaude` (`claudeMd`, `paths`, `hooks`), `hasGitignoreClaude`.
2. Read the reference list: `ls "$SKILL/templates" "$SKILL/templates/rules"` — `CLAUDE.md`, `rules/{workflow,architecture,knowledge,pitfalls,commands}.md`, `settings.json`, `conventions.json`, `gitignore`. Read each template once so the mapping names real sections.
3. Read every existing file listed in `existingClaude.paths` and `CLAUDE.md` when present. A hook under `.claude/hooks/` whose name or behaviour matches a plugin hook (`guard-git`, `deps-exact`, `pr-size`, `format`, `branch-info`, or an older per-repo spelling of the same check — exact-pin guard, formatter-on-save, branch banner) is a duplicate.

## Step 2 — propose, then STOP

Print, in this order, and nothing else:

1. **Evidence** (≤ 6 lines): package manager + lockfile, formatter + config file, apps guess with paths, branches with the default, CI workflow files and parser, existing Claude files.
2. **Mapping table**, one row per template plus one per existing file:

   | source | action | target |
   |---|---|---|
   | `templates/CLAUDE.md` | keep / adapt / drop | `CLAUDE.md` |
   | `templates/rules/workflow.md` | keep | `.claude/rules/workflow.md` |
   | … | | |
   | `templates/rules/commands.md` | adapt (one per app) | `.claude/rules/<app>/commands.md` or `.claude/rules/commands.md` |
   | `.claude/hooks/<x>.sh` (existing) | drop — duplicate of plugin hook `<y>` | — |
   | `CLAUDE.md` (existing) | merge / keep as is | `CLAUDE.md` |

   `keep` = render as is; `adapt` = render then edit for this repo (say what); `drop` = not written (say why). An existing target file is never overwritten silently: propose `merge` (template-owned sections added, the rest untouched) or `keep as is`, and the user picks. Only mention tooling the discovery found: a rule line naming a tool the repo does not have is edited out under `adapt`.
3. **Open questions** — only those the discovery could not settle; give the detected default for each:
   - integration branch (`develop` if present, else the default branch — say when both coincide, that is a one-branch flow and the hooks will report it);
   - production branch = `defaultBranch`, and a one-clause deploy note (empty when nothing deploys automatically);
   - PR size cap (default 400 lines / 15 files, label `large-pr`);
   - which guessed dirs are apps (libraries usually dropped; none → single-app repo);
   - is `.claude/` committed (default yes → `.gitignore` negations; no → `.claude/` ignored entirely, only `CLAUDE.md` tracked).

Then **STOP and wait for the user's answers**. Do not write, render or run anything else in this turn.

## Step 3 — write (after confirmation only)

Run the commands you will write **before** writing them. Every command that lands in a `commands.md` or in `settings.json` permissions must be either quoted verbatim from `ciWorkflows[].jobs[].run[]` or run once here with exit 0 — refuse anything else and say so (`not written: <command> — not in CI and not run`). Keep the outputs; the report quotes them.

1. **`.claude/conventions.json`** — build the answers file, render, set `apps`:
   ```bash
   mkdir -p .claude
   jq -n --arg int "<integration>" --arg prod "<production>" --arg pm "<pm>" --arg fmt "<formatter>" \
     --arg note "<deploy note or empty>" --argjson lines <lines> --argjson files <files> \
     '{integrationBranch:$int, productionBranch:$prod, packageManager:$pm, formatter:$fmt,
       prSize:{lines:$lines, files:$files}} + (if $note == "" then {} else {deployNote:$note} end)' > /tmp/answers.json
   "$SKILL/scripts/render.sh" "$SKILL/templates/conventions.json" /tmp/answers.json \
     | jq --argjson apps '<{"name":"path",…} or {}>' --arg note "<deploy note or empty>" \
       '(if $apps == {} then del(.apps) else .apps = $apps end) | (if $note == "" then . else .deployNote = $note end)' \
     > .claude/conventions.json
   ```
   Existing `.claude/conventions.json` with `merge` chosen: the rendered file is the base and the existing keys win — `jq -s '.[0] * .[1]' <rendered> .claude/conventions.json`. `packageManager` unset in the discovery → ask which one before rendering (the templates need it). `deployNote` stays in the file when set: `--refresh` re-renders `{{DEPLOY_NOTE}}` from it.
2. **Rendered rules** — for each template kept or adapted:
   ```bash
   mkdir -p .claude/rules
   for f in workflow architecture knowledge pitfalls; do
     "$SKILL/scripts/render.sh" "$SKILL/templates/rules/$f.md" .claude/conventions.json > ".claude/rules/$f.md"
   done
   ```
   Then apply the `adapt` edits announced in step 2 outside the sentinel comments only (`<!-- conventions:begin … -->` / `<!-- conventions:end … -->` wrap the template-owned text that `--refresh` rewrites). Fill the **Test layout** table in `architecture.md` with the layers the repo actually has (rows = layer, source glob, test dir, test kind, relative to the app dir; keep `other`); it sits outside the sentinels and belongs to the project.
3. **`CLAUDE.md`** — write the app table to `/tmp/app-table.md`, then render:
   - multi-app: `| App | Path | Stack | Verify |` + `|---|---|---|---|` + one row per app, Verify = `` `.claude/rules/<app>/commands.md` ``;
   - single-app: one line instead of a table, e.g. `` Single app (<stack>). Verify: `.claude/rules/commands.md`. ``;
   ```bash
   "$SKILL/scripts/render.sh" "$SKILL/templates/CLAUDE.md" .claude/conventions.json --app-table /tmp/app-table.md > CLAUDE.md
   ```
   Existing `CLAUDE.md` with `merge` chosen: keep the existing text, append the template's sentinel sections that are missing. Keep the file ≤ 40 lines.
4. **Command sheets** — one `.claude/rules/<app>/commands.md` per app (single-app: `.claude/rules/commands.md`, without the `paths:` frontmatter), following `templates/rules/commands.md`: the sequence line lists the commands in CI order, joined by `&&`, from the repo root; a command that needs an environment variable is marked `(needs <VAR>)` and excluded from the `&&` line. Replace every `<app>`, `<app-path>`, `<command …>`, `<VAR>` slot; delete the bullets that do not apply. Source of each command, in preference order: the CI job's `run:` lines for that app; else the app's `packageScripts` invoked the repo way (`<pm> --filter <name> <script>`, `<pm> run <script>`, …) and run once. Run the finished sequence once from the repo root and record the output.
5. **`.claude/settings.json`** — `/tmp/permissions.json` = a JSON array of `Bash(<prefix>*)` entries, one per command family actually run or quoted in this session (e.g. `Bash(<pm> lint*)`, `Bash(<pm> test*)`, `Bash(<pm> --filter *)`), plus the read-only git/gh set `Bash(git status*)`, `Bash(git diff*)`, `Bash(git log*)`, `Bash(git branch*)`, `Bash(gh pr view*)`, `Bash(gh pr checks*)`, `Bash(gh run view*)`, `Bash(gh run list*)`. Then:
   ```bash
   "$SKILL/scripts/render.sh" "$SKILL/templates/settings.json" .claude/conventions.json --permissions /tmp/permissions.json | jq . > .claude/settings.json
   ```
   No `hooks` key — hooks come from the plugin. An existing `settings.json`: merge `permissions.allow` / `permissions.deny` (union) and add `enabledPlugins: {}` only when absent; remove a `hooks` entry only when step 2 marked it as a duplicate and the user agreed.
6. **`.gitignore`** — `.claude/` committed: append `"$SKILL/templates/gitignore"` unless `hasGitignoreClaude` is true, in which case show the existing `.claude` lines and add only the missing negations. Not committed: append a single `.claude/` line instead.
7. Final check, then report:
   ```bash
   grep -rn '{{[A-Z_]*}}\|TODO' CLAUDE.md .claude/rules .claude/settings.json .claude/conventions.json
   grep -n '<app>\|<app-path>\|<command\|<VAR>' .claude/rules/*/commands.md .claude/rules/commands.md 2>/dev/null
   git status --short
   ```
   Any hit from the two greps is a slot left unfilled — fix it before reporting (`<app>` inside the generic rules' prose, e.g. `.claude/rules/<app>/`, is template text and is not checked).
   Report (≤ 25 lines): the exact files written, per `commands.md` the command run and the last line of its output, permissions added, what was merged or left untouched, and the one-line reminder `not committed — review with git diff, then commit yourself`.

## Refresh (`--refresh`)

No discovery, no questions, no other write. Run, then show the result:

```bash
"$SKILL/scripts/refresh.sh" "$(git rev-parse --show-toplevel)"
git diff --stat
```

`refresh.sh` re-renders, from the current `.claude/conventions.json`, the sentinel sections of every template that has some (`CLAUDE.md`, `rules/workflow.md`, `rules/architecture.md`, `rules/knowledge.md`, `rules/pitfalls.md`) and, for each target file that exists and carries sentinels, replaces the body of each matching `<!-- conventions:begin <id> -->` … `<!-- conventions:end <id> -->` pair; every byte outside the pairs stays as it is. A section present in the template but missing from the file is appended at the end after a one-line `<!-- conventions:refresh — … -->` notice — tell the user to move it where it belongs. Never touched: files without any sentinel (a kept-as-is `CLAUDE.md`), `.claude/conventions.json`, `.claude/settings.json`, `.gitignore`, every `commands.md`, `.claude/rules/<app>/`, the `pitfalls.md` entries and the **Test layout** table. The script prints the changed files (one per line, `refresh: nothing to change` on stderr when none) and exits 0; it exits 1 without writing when `.claude/conventions.json` is missing or lacks a value a section needs (the placeholder is named — add the key and re-run) or when a section in a target file has no end marker (fix the file by hand first).

Report: the `git diff --stat` output, the appended sections if any, and the reminder `not committed — review with git diff, then commit yourself`.
