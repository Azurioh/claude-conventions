---
name: pr
description: Opens the current branch's pull request the repo way — conventional title, body with what/why/verification, base = the integration branch from .claude/conventions.json — and, when the diff exceeds the configured size cap, splits it into a GitHub-native stack of chained PRs by logical group. Use for every PR instead of a raw gh pr create, and whenever the user says "open a PR", "create the PR" or "stack this".
argument-hint: "[--stack] [<title>]"
---
Read the repo values first (all from `.claude/conventions.json`; stop and ask the user to run `/conventions:port-claude-config` if the file or `integrationBranch` is missing):

```bash
INT="$(jq -r '.integrationBranch' .claude/conventions.json)"
PROD="$(jq -r '.productionBranch // empty' .claude/conventions.json)"
[ -n "$PROD" ] || PROD="$(git symbolic-ref -q --short refs/remotes/origin/HEAD | sed 's#^origin/##')"
[ -n "$PROD" ] || PROD=main
LINES="$(jq -r '.prSize.lines // 400' .claude/conventions.json)"
FILES="$(jq -r '.prSize.files // 15' .claude/conventions.json)"
LABEL="$(jq -r '.prSize.label // "large-pr"' .claude/conventions.json)"
jq -r '.prSize.exclude[]?' .claude/conventions.json
```

Default excludes when `prSize.exclude` is absent: `**/pnpm-lock.yaml`, `**/package-lock.json`, `**/yarn.lock`, `**/migrations/**`, `**/components/ui/**`. Turn every exclude glob into a git pathspec `':!<glob>'`.

Preconditions: working tree clean; `git fetch origin "$INT"`; current branch is neither `$PROD` nor `$INT`.

1. Measure: `git diff --numstat "origin/$INT...HEAD" -- . ':!<exclude-1>' ':!<exclude-2>' …` → changed lines (adds + dels) and file count. Commits: `git log --oneline "origin/$INT..HEAD"`.
2. Tidy commits first: every commit `<type>(scope): description`, one logical change each; fold `wip` / `fix typo` / `address review` commits with `git commit --fixup <sha>` + `git rebase --autosquash "origin/$INT"` (never interactive). Stop and ask if a rebase conflicts.
3. **Within the cap (≤ `$LINES` lines and ≤ `$FILES` files) and `--stack` not requested → single PR:**
   - Title: `$ARGUMENTS` when given, else `<type>(scope): description` (≤ 72 chars). Body sections: `## What`, `## Why`, `## Verification` (the exact commands run, e.g. the output of `/conventions:verify-app`), `## Notes` (migrations, env vars, follow-ups).
   - `gh pr create --base "$INT" --title "<title>" --body-file <tmp>`.
4. **Over the cap, or `--stack` → stack:**
   - Group the commits into N logical PRs (by app when `apps` is set in `conventions.json`, then by layer: contract/domain → application → infrastructure → UI; tests travel with their code). Show the proposed split (group → commits → lines/files) and wait for approval.
   - One branch per group, named after its content (`chore/claude-hooks`, `docs/api-rules`) — never numbered. Build each by cherry-picking its commits onto the previous group's branch (group 1 onto `origin/$INT`); do not push yet.
   - Use GitHub's native stack: `gh extension install github/gh-stack` if `gh stack` is missing, then `gh stack link --base "$INT" --open <branch-1> <branch-2> … <branch-N>` (bottom → top). It pushes the branches, creates the PRs with the right base chain and registers the stack. **Always pass `--base "$INT"`**: the default is the repo's default branch, and a stacked PR's base cannot be edited afterwards (`gh stack unstack <n>`, fix, link again). Verify with `gh pr view <bottom> --json baseRefName`.
   - Then `gh pr edit <n> --title "<type>(scope): description" --body-file <tmp>` for every PR with the single-PR body (no `[i/N]`, no manual stack list — GitHub shows the stack). Later changes: commit on the right branch, `gh stack rebase --no-trunk`, `gh stack push`.
5. Never pass `--label "$LABEL"` yourself; only the user decides that (`gh pr edit <n> --add-label "$LABEL"` after approval).
6. Report: PR URL(s), the measured size against the cap, and for a stack the `gh stack view` output.
