# Workflow

<!-- conventions:begin workflow.branches -->
## Branches

- `{{PRODUCTION_BRANCH}}` = production{{DEPLOY_NOTE}}. `{{INTEGRATION_BRANCH}}` =
  integration branch. **Every PR targets `{{INTEGRATION_BRANCH}}`.** Release =
  deliberate PR `{{INTEGRATION_BRANCH}} → {{PRODUCTION_BRANCH}}` via `/conventions:release`.
- Branch off the integration branch:
  `git switch {{INTEGRATION_BRANCH}} && git pull && git switch -c feat/<name>`.
- Never commit directly on `{{PRODUCTION_BRANCH}}` or `{{INTEGRATION_BRANCH}}`;
  never force-push (the plugin hooks refuse both).
<!-- conventions:end workflow.branches -->

<!-- conventions:begin workflow.commits -->
## Commits

- Format `<type>(scope): description` — types: feat, fix, refactor, docs,
  test, chore, perf, ci, release. English only.
- One logical change per commit. No `wip` / `fix typo` / `address review`
  commits in a PR — fold them first: `git commit --fixup` +
  `git rebase --autosquash`.
- **Never commit without the user's OK.**
<!-- conventions:end workflow.commits -->

<!-- conventions:begin workflow.pr -->
## PR hygiene

- Open every PR with `/conventions:pr`, never a raw `gh pr create`. Title uses
  the same `<type>(scope): description` format. Body states what/why and the
  verification command that was run.
- **Size cap: ≤ {{PR_SIZE_LINES}} changed lines (additions + deletions) and
  ≤ {{PR_SIZE_FILES}} files**, excluding lockfiles, generated migrations and
  vendored UI components (`prSize.exclude` in `.claude/conventions.json`). The
  `pr-size` hook blocks `gh pr create` beyond the cap unless
  `--label {{PR_SIZE_LABEL}}` is passed explicitly (mass renames / generated
  code only).
- Bigger change → **GitHub native stack** via `/conventions:pr --stack`: one
  branch + PR per logical group, branch names describe the content (never
  numbered), linked with `gh stack link --base {{INTEGRATION_BRANCH}} <branches
  bottom→top>`. GitHub shows the order, diffs per layer and retargets bases
  automatically on merge.
<!-- conventions:end workflow.pr -->

<!-- conventions:begin workflow.deps -->
## Dependencies

- New dependencies are added exact-pinned at the latest stable version from the
  registry: `{{PKG_MANAGER}} add {{PKG_EXACT_FLAG}} <pkg>` (the `deps-exact` hook
  refuses the unpinned form). Existing caret ranges are not retrofitted. Never
  hand-edit a manifest or a lockfile.
- Security advisories on transitives → `/conventions:deps-audit` (direct
  dependency bump first, override/resolution pin for transitives).
<!-- conventions:end workflow.deps -->

<!-- conventions:begin workflow.worktrees -->
## Shared worktrees

- Never bare `git stash` / `git stash pop` (the stash stack is shared across
  worktrees). Use `git stash push -u -m <tag>`, then
  `git stash list --format='%H %gs'` to find it, then `git stash apply <sha>`.
<!-- conventions:end workflow.worktrees -->

<!-- conventions:begin workflow.verification -->
## Verification and discovery

- CI parity per app: the sequence in `.claude/rules/<app>/commands.md`
  (single-app repo: `.claude/rules/commands.md`), run in file order from the
  repo root. `/conventions:verify-app <app|all>` runs it — do this before
  claiming a task done.
- Cross-cutting rules (dead code, ports/adapters, tests) live in
  `architecture.md`; test gaps → `/conventions:test-gaps <app|all>`.
- Long-term choices → `/conventions:adr`; recurring traps → `pitfalls.md`
  (see `knowledge.md`).
<!-- conventions:end workflow.verification -->
