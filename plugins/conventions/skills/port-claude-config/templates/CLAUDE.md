<!-- conventions:begin claude.intro -->
Claude Code conventions for this repository. The rules live in `.claude/rules/`
(`workflow.md`, `architecture.md`, `knowledge.md` always apply; `pitfalls.md`
collects recurring traps; a `commands.md` per app holds its CI sequence). Hooks,
skills and agents come from the `conventions` plugin, not from this repo.
<!-- conventions:end claude.intro -->

## Stack

{{APP_TABLE}}

<!-- conventions:begin claude.branches -->
## Branches

`{{PRODUCTION_BRANCH}}` is **production**{{DEPLOY_NOTE}}. `{{INTEGRATION_BRANCH}}` is
the integration branch. **Every PR targets `{{INTEGRATION_BRANCH}}`, never
`{{PRODUCTION_BRANCH}}`.** A PR against `{{PRODUCTION_BRANCH}}` is wrong whatever
it contains — retarget it before reviewing.

    git switch {{INTEGRATION_BRANCH}} && git pull && git switch -c feat/my-change
    /conventions:pr
<!-- conventions:end claude.branches -->

<!-- conventions:begin claude.commands -->
## Commands

- Verification = the app's `commands.md` sequence, run through
  `/conventions:verify-app <app|all>` before claiming a task done.
- Dependencies: `{{PKG_MANAGER}} add {{PKG_EXACT_FLAG}} <pkg>` (exact pin, latest
  stable from the registry); never hand-edit a manifest or lockfile.
- `/conventions:pr` opens the PR (size cap {{PR_SIZE_LINES}} lines / {{PR_SIZE_FILES}}
  files, stacked PRs beyond); `/conventions:test-gaps` lists untested changes;
  `/conventions:adr` records a long-term decision; `/conventions:release` prepares
  `{{INTEGRATION_BRANCH}} → {{PRODUCTION_BRANCH}}`; `/conventions:deps-audit` fixes advisories.
<!-- conventions:end claude.commands -->
