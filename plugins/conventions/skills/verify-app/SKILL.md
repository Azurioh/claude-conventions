---
name: verify-app
description: Runs one app's exact CI sequence locally (an app named in .claude/conventions.json#apps, or all) in a forked verifier context and returns a triage with exact error text. Use before claiming any change done and before opening a PR. Prerequisite - a `verifier` agent must exist in ~/.claude/agents/ (this skill forks into it).
argument-hint: "<app|all>"
context: fork
agent: verifier
---
Run the CI-parity sequence for `$ARGUMENTS` from the repo root. Do not fix anything.

1. Resolve the apps:
   ```bash
   jq -r '.apps // {} | to_entries[] | "\(.key)\t\(.value)"' .claude/conventions.json
   ```
   - Output non-empty → multi-app repo. `$ARGUMENTS` must be one of the keys or `all`; anything else → stop with `unknown app <x>; known: <keys>`.
   - Output empty → single-app repo. `$ARGUMENTS` is ignored; the only app is the repo itself.
2. Locate each app's command sheet: `.claude/rules/<app>/commands.md` (multi-app) or `.claude/rules/commands.md` (single-app). Missing sheet → report `FAIL no command sheet at <path>` for that app and move on; never invent a sequence.
3. Run the sheet's commands exactly as written, in file order, each in its own `Bash` call from the repo root. A setup step the sheet lists first (build shared packages, generate a client) is part of the sequence — run it before the rest. Stop the app's sequence at the first failure; with `all`, continue with the next app.
4. When the sheet marks a command as depending on an environment variable (a database URL, a token) and that variable is unset, do not run it: report `skipped (<VAR> unset)` for that command and continue the sequence.

Report (≤ 30 lines): per app `PASS` / `FAIL <command>` / `skipped (<VAR> unset)`; for each failure the error verbatim (≤ 10 lines), `file:line`, suspected root cause in one sentence.
