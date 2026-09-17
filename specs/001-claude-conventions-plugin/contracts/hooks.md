# Contract: plugin hooks

Registered in `plugins/conventions/hooks/hooks.json`:

| Event | Matcher | Script | Timeout | Blocks? |
|---|---|---|---|---|
| PreToolUse | `Bash` | `${CLAUDE_PLUGIN_ROOT}/hooks/guard-git.sh` | 10 s | yes (exit 2) |
| PreToolUse | `Bash` | `${CLAUDE_PLUGIN_ROOT}/hooks/deps-exact.sh` | 10 s | yes (exit 2) |
| PreToolUse | `Bash` | `${CLAUDE_PLUGIN_ROOT}/hooks/pr-size.sh` | 20 s | yes (exit 2) |
| PostToolUse | `Edit\|Write` | `${CLAUDE_PLUGIN_ROOT}/hooks/format.sh` | 30 s | never |
| SessionStart | — | `${CLAUDE_PLUGIN_ROOT}/hooks/branch-info.sh` | 5 s | never |

Input: stdin JSON from Claude Code (`tool_name`, `tool_input.command` / `tool_input.file_path`,
`cwd`). Project root: `$CLAUDE_PROJECT_DIR`, fallback `cwd`.

Output: deny = exit 2 + single stderr line `conventions/<hook>: <reason>`; pass = exit 0,
no stdout (except `branch-info.sh`, whose stdout is session context). Missing
`conventions.json` when a value is required = stderr warning `conventions/<hook>:
.claude/conventions.json missing — skipped`, exit 0. Outside a git repo = exit 0 silently.

Behaviour (per hook):

- `guard-git.sh`: refuse `git push --force|-f|--force-with-lease` to protected branches;
  refuse bare `git stash` / `git stash pop`; refuse `git commit` / `git push` while on a
  protected branch; refuse `gh pr create` whose `--base` is the production branch,
  except the release pair (`--base <production> --head <integration>`); any other base
  (integration or a stacked feature branch) passes.
- `deps-exact.sh`: refuse `<pm> add|install <pkg>` without the exact-pin flag for the detected
  package manager; ambiguous/undetected package manager → warning, pass.
- `pr-size.sh`: on `gh pr create`, compute `git diff --numstat <base>...HEAD` minus excluded
  globs; refuse when lines > `prSize.lines` or files > `prSize.files` unless
  `--label <prSize.label>` is present; skip for the release pair.
- `format.sh`: if the edited file has a formatter-relevant extension, run
  `biome check --write <file>` or `prettier --write <file>` through
  `node_modules/.bin/<formatter>` (else the formatter on PATH, else skip); never fails.
- `branch-info.sh`: print current branch, upstream state, and a warning when on a protected
  branch; on invalid `conventions.json` print the validation message.
