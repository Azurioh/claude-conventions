---
name: release
description: Prepares the deliberate release PR from the integration branch to the production branch (both from .claude/conventions.json) — changelog grouped by app, conventional title, deploy notes — and waits for checks. Never merges. Use only when the user asks to release / ship / deploy the integration branch.
disable-model-invocation: true
---
Read the branches:

```bash
INT="$(jq -r '.integrationBranch' .claude/conventions.json)"
PROD="$(jq -r '.productionBranch // empty' .claude/conventions.json)"
[ -n "$PROD" ] || PROD="$(git symbolic-ref -q --short refs/remotes/origin/HEAD | sed 's#^origin/##')"
[ -n "$PROD" ] || PROD=main
jq -r '.apps // {} | to_entries[] | "\(.key)\t\(.value)"' .claude/conventions.json
```

Preconditions: `git fetch origin "$INT" "$PROD"`; working tree clean; you are NOT on `$PROD`.

1. `git log --oneline "origin/$PROD..origin/$INT"` → if empty, stop: nothing to release.
2. Group commits by app: match the commit scope, else the touched paths (`git show --stat --format= <sha>`), against the `apps` keys and paths. Commits touching no app path go to `repo` (shared packages, CI, config). Single-app repo (no `apps`) → one group named after the repo.
3. Title: `release: <3-6 word summary of the main themes>`. Body: one `### <group>` section per group, one bullet per commit (`<subject> (#<pr>)`), then a `### Deploy notes` section listing:
   - migrations: every file added or changed under any `**/migrations/` directory — `git diff --name-only "origin/$PROD..origin/$INT" | grep -E '(^|/)migrations/'`;
   - new environment variables: names introduced in the diff (`git diff "origin/$PROD..origin/$INT" | grep -E '^\+.*(process\.env\.|import\.meta\.env\.|env\(")' ` and changes to `.env.example` / `.env.template`);
   - `none` for each empty list.
4. Show title + body to the user and wait for approval.
5. `gh pr create --base "$PROD" --head "$INT" --title "<title>" --body-file <tmp>`; then `gh pr checks <n> --watch`. This head/base pair is the one PR exempt from the size cap; nothing else is.
6. Report the PR URL and check status. Never merge, never push to `$PROD`.
