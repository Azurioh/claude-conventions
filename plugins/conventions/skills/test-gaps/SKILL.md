---
name: test-gaps
description: Reports which changed source files have no matching test, using the "Test layout" table in .claude/rules/architecture.md to know where each layer's tests live. Use before claiming a change done and before opening a PR; the test-writer agent fills the gaps it reports. Prerequisite - a `verifier` agent must exist in ~/.claude/agents/ (this skill forks into it).
argument-hint: "<app|all>"
context: fork
agent: verifier
---
Read-only. Never write or edit tests.

1. Resolve the app dirs for `$ARGUMENTS`:
   ```bash
   INT="$(jq -r '.integrationBranch' .claude/conventions.json)"
   jq -r '.apps // {} | to_entries[] | "\(.key)\t\(.value)"' .claude/conventions.json
   ```
   Non-empty → `$ARGUMENTS` is one key (its path) or `all` (every path). Empty → single-app repo: the dir is `.` whatever `$ARGUMENTS` says.
2. Read the "Test layout" table in `.claude/rules/architecture.md` (columns `layer | source glob | test dir | test kind`; globs and dirs are relative to the app dir). No table → stop and report `no "Test layout" table in .claude/rules/architecture.md — add it (or run /conventions:port-claude-config --refresh)`. Never fall back to a guessed layout.
3. For each app: `git diff --name-only "origin/$INT...HEAD" -- <app-dir>`, keep source files only (drop test files, generated files, config, docs, lockfiles).
4. Classify each changed file by the first table row whose source glob matches its path relative to the app dir; no matching row → layer `other`, test kind `unit`, test dir = the app's default test dir (the row named `other` if present, else `tests`).
5. Look for coverage, in order — first hit wins, record its path:
   - a same-named `*.test.*` / `*.spec.*` next to the file;
   - a file with the same basename under the row's test dir;
   - a test under that dir importing it: `grep -rl "<basename-without-extension>" <app-dir>/<test dir> 2>/dev/null`.

Output (≤ 30 lines): a table with columns `file — layer — PRESENT <path> or MISSING — expected test kind`, one row per changed file, grouped by app when `$ARGUMENTS` is `all`. End with one line: `<N> file(s) MISSING a test` or `all changed files covered`.
