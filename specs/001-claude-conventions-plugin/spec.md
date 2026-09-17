# Feature Specification: Claude Conventions Plugin

**Feature Branch**: `001-claude-conventions-plugin`

**Created**: 2026-09-17

**Status**: Implemented

**Input**: User description: "claude-conventions: a personal Claude Code plugin marketplace that packages the reusable part of the bsk-apps `.claude/` configuration so any of my repos gets the same guardrails in one install."

## Context

Today every repository re-writes its Claude Code guardrails by hand: the git guard,
the exact-pin dependency guard, the PR size cap, the post-edit formatter, the
generic skills (`pr`, `verify-app`, `test-gaps`, `adr`, `release`, `deps-audit`) and
the generic agents (`ci-triage`, `rules-reviewer`, `test-writer`, `repo-explorer`).
Copies drift, and a stale copy silently loses a rule. The reference implementation
lives in `bsk-apps/.claude` (branch `docs/claude-config-spec`).

This feature extracts the reusable layer into one repository that each project
installs once and updates centrally. Project-specific material (per-app rules,
per-app agents, scaffold skills) stays in each project and is out of scope here.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install the guardrails into a repo in one step (Priority: P1)

As the owner of a repository, I install the conventions once (through my existing
`ccprofile` tooling) and, in the next Claude Code session, the git guard, the
dependency guard, the PR size cap, the formatter hook and the branch info banner are
active, and the generic skills and agents are available — without copying any file
by hand.

**Why this priority**: it is the whole point of the feature; without it nothing else
delivers value.

**Independent Test**: on an empty fixture repository with a lockfile and a formatter
config, apply the profile, start a session, and observe that a forbidden git command
is blocked, a non-pinned dependency add is blocked, the session banner shows the
branch, and `/pr`, `/verify-app`, `/adr` are listed as available skills.

**Acceptance Scenarios**:

1. **Given** a repo with no `.claude/` directory, **When** I apply the `conventions`
   profile, **Then** the plugin is recorded in the repo's local Claude settings and the
   marker file, and no shared file is modified.
2. **Given** the plugin is installed and the repo declares its integration branch,
   **When** a session runs `git push --force` or a bare `git stash`, **Then** the
   command is refused with a one-line reason.
3. **Given** the plugin is installed, **When** a session adds a dependency without an
   exact pin, **Then** the command is refused and the corrected form is suggested.
4. **Given** the plugin is installed, **When** a session edits a source file,
   **Then** the file is formatted with the repo's own formatter right after the edit.
5. **Given** the plugin is installed, **When** a session opens a PR whose diff exceeds
   the size cap, **Then** the PR creation is blocked unless the explicit large-PR
   label is passed.

---

### User Story 2 - Port the rules into a new repository (Priority: P2)

As the owner of a freshly tooled repository, I run the port skill; it discovers my
stack, CI sequences and branches, shows me a mapping table and the questions it
cannot answer alone, and — only after I confirm — writes the conventions file, the
filled rule templates, the settings file and the per-app command sheets.

**Why this priority**: hooks alone give guardrails; rules give Claude the working
agreements (branching, commits, PR hygiene, architecture, knowledge capture). This is
the second half of "equivalent to bsk-apps".

**Independent Test**: run the port skill on a fixture monorepo with two apps and a CI
workflow; verify it stops at the mapping table, then after confirmation produces
`CLAUDE.md`, the four generic rule files with placeholders resolved, one
`commands.md` per app whose commands match the CI workflow verbatim, `settings.json`
with an empty `enabledPlugins` object, and the `.gitignore` negations.

**Acceptance Scenarios**:

1. **Given** a repo with a CI workflow and two apps, **When** I run the port skill,
   **Then** it presents a mapping table (reference file → keep / adapt / drop → target
   path) and at most the questions that change the output (integration branch, size
   cap, deploy branches, whether `.claude/` is committed), and writes nothing yet.
2. **Given** I confirm the mapping, **When** the skill writes, **Then** every command
   written into a rule or command sheet was either run once successfully in the repo
   or quoted verbatim from a CI workflow.
3. **Given** the repo already has a `CLAUDE.md` or rule files, **When** the skill
   writes, **Then** existing files are merged or left untouched, never overwritten
   without an explicit confirmation.
4. **Given** the repo uses a stack the reference never had (e.g. no Prisma), **When**
   the skill writes rules, **Then** no rule references tooling the repo does not have.

---

### User Story 3 - Update once, propagate everywhere (Priority: P3)

As the maintainer of several repos, when I improve a hook, a skill or an agent in
`claude-conventions`, every consuming repo picks it up on the next plugin update with
no re-port; when I improve a rule template, re-running the port skill refreshes the
generic rules without touching project-specific files.

**Why this priority**: drift prevention is the reason the feature exists, but it
only matters once the first two stories work.

**Independent Test**: install the plugin in a fixture repo, change a hook message in
the plugin, update the plugin, and observe the new message in the fixture without
any file change in the fixture; then change a template line, re-run the port skill
in refresh mode, and observe that only the generic rule file changed.

**Acceptance Scenarios**:

1. **Given** a consuming repo, **When** the plugin is updated, **Then** hook, skill
   and agent behaviour changes without editing the consuming repo.
2. **Given** a consuming repo with hand-edited per-app rules, **When** the port skill
   is re-run in refresh mode, **Then** per-app rules, `pitfalls.md` entries and the
   `CLAUDE.md` app table are preserved and only template-owned sections are updated.

---

### User Story 4 - Hooks resolve their values without configuration (Priority: P3)

As a repo owner with standard tooling, I do not configure anything beyond the
integration branch: the package manager is detected from the lockfile, the formatter
from its config file, the size cap uses the default; when I need something unusual I
override it in the conventions file.

**Why this priority**: keeps install at "one step" for the common case and avoids a
config file that must be kept in sync with the repo.

**Independent Test**: three fixture repos — pnpm + Biome, npm + Prettier, and one
with no conventions file — each hook must behave correctly (or warn and pass
through) in all three.

**Acceptance Scenarios**:

1. **Given** a repo with a `pnpm-lock.yaml` and a `biome.json`, **When** any hook
   runs, **Then** it uses pnpm and Biome without any conventions file entry.
2. **Given** a repo with `package-lock.json` and a Prettier config, **When** the
   formatter hook runs, **Then** it formats with Prettier through npm.
3. **Given** a repo whose conventions file overrides the size cap, **When** the PR
   size hook runs, **Then** the override wins over the default.
4. **Given** a repo with no conventions file, **When** a hook that needs the
   integration branch runs, **Then** it prints a one-line warning naming the missing
   file and does not block the command.

---

### Edge Cases

- Two lockfiles present (e.g. `package-lock.json` and `pnpm-lock.yaml`): the
  conventions file must state the package manager; without it the hook warns and
  skips the dependency guard rather than guessing.
- No formatter config found: the formatter hook does nothing and stays silent.
- The command runs outside a git repository (e.g. a scratch directory): git-related
  hooks pass through silently.
- A consuming repo already ships a hook with the same purpose (pre-existing
  `.claude/hooks/`): both run; the port skill's mapping table flags the duplicate and
  proposes removing the local copy.
- Integration branch declared but missing on the remote: the PR skill reports it and
  stops instead of falling back to the default branch.
- Port skill run on a single-app repo: no app table is generated; `CLAUDE.md` uses
  the single-app layout.
- The size cap is exceeded only by excluded paths (lockfile, generated migrations,
  vendored UI): the exclusion list applies before the cap is evaluated.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repository MUST be installable as a Claude Code plugin marketplace
  exposing one plugin named `conventions`.
- **FR-002**: The plugin MUST provide these hooks: git guard (refuses force push and
  bare stash, protects the integration branch), exact-pin dependency guard, PR size
  cap with the explicit large-PR escape hatch and the exclusion list, post-edit
  formatter, and session-start branch info.
- **FR-003**: Hooks MUST resolve the package manager from the lockfile, the
  formatter from its config file, and the size cap from a default (400 changed
  lines, 15 files), and MUST accept overrides for each from a per-repo conventions
  file at `.claude/conventions.json`.
- **FR-004**: The integration branch MUST be read from the conventions file and is
  the only mandatory value; when absent, hooks that need it MUST warn once per
  invocation and let the command through.
- **FR-005**: The plugin MUST ship the generic skills `pr`, `verify-app`, `test-gaps`,
  `adr`, `release`, `deps-audit` and the generic agents `ci-triage`, `rules-reviewer`,
  `test-writer`, `repo-explorer`, each rewritten so that nothing in them names a
  bsk-apps application, branch, package manager or tool.
- **FR-006**: The plugin MUST NOT contain any per-app rule, per-app agent or scaffold
  skill.
- **FR-007**: The repository MUST provide rule templates for `CLAUDE.md`,
  `workflow.md`, `architecture.md`, `knowledge.md` and `pitfalls.md` with
  placeholders for the integration branch, package manager, formatter, size cap and
  the application table.
- **FR-008**: The plugin MUST ship a `port-claude-config` skill that, in order:
  discovers the target repo (layout, package manager, formatters, linters, test
  runners, CI workflows, branches, existing Claude config) with evidence; presents a
  mapping table and the open questions; waits for confirmation; then writes the
  conventions file, the resolved templates, `settings.json` (permissions derived
  from real commands, force-push denied, `enabledPlugins` present and empty), the
  `.gitignore` negations, and one `commands.md` per app mirroring CI.
- **FR-009**: The port skill MUST refuse to write a command it has not run
  successfully or quoted verbatim from a CI workflow, and MUST NOT leave placeholders
  or TODOs in the output.
- **FR-010**: The port skill MUST support a refresh mode that re-applies template
  changes while preserving project-specific content.
- **FR-011**: The port skill MUST NOT commit.
- **FR-012**: A `ccprofile` profile named `conventions` MUST exist so that
  `ccprofile apply conventions` installs the plugin following ccprofile's routing
  rules (local settings when the shared settings own `enabledPlugins`).
- **FR-013**: The repository MUST ship an automated hook test suite running against
  fixture repositories covering pnpm + Biome, npm + Prettier, and a repo without a
  conventions file.
- **FR-014**: The repository MUST document install, per-project setup, value
  resolution and the update path in its README.

### Key Entities

- **Plugin**: the installable unit; owns hooks, skills, agents; versioned by the
  repository.
- **Conventions file**: per-repo values (integration branch mandatory; package
  manager, formatter, size cap, exclusion list optional) that hooks read.
- **Rule template**: a generic rule file with placeholders; owned by the repository,
  copied and resolved into a project by the port skill.
- **Target repo config**: what the port skill produces in a project (`CLAUDE.md`,
  rules, settings, conventions file, command sheets).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A fresh repository goes from "no Claude config" to "hooks active and
  generic skills available" with one profile command and zero files copied by hand.
- **SC-002**: The port skill produces, on a fixture monorepo, a configuration in
  which 100% of the commands in rule files and command sheets execute successfully
  in that repo.
- **SC-003**: The hook test suite passes on all three fixture repositories.
- **SC-004**: Changing a hook message in the plugin and updating it changes the
  observed behaviour in a consuming repo with zero file changes in that repo.
- **SC-005**: Re-running the port skill in refresh mode on a repo with hand-written
  per-app rules leaves every per-app file byte-identical.
- **SC-006**: The plugin passes Claude Code's own plugin validation.

## Assumptions

- The user is a solo developer; no multi-user permissions or team distribution
  concerns.
- Consuming repos are JavaScript/TypeScript projects with a lockfile; other
  ecosystems are not targeted in this version.
- Claude Code plugins cannot ship rules; rules therefore live as templates copied
  into projects, and hooks/skills/agents live in the plugin.
- `ccprofile` (patched 2026-09-17) is the distribution mechanism; the plugin is
  referenced through this repository as a marketplace.
- The reference implementation to extract from is `bsk-apps/.claude` on branch
  `docs/claude-config-spec`; bsk-apps itself is not migrated in this feature.
- Merging with `quodalia/ai-setup` and anything from the user's global `~/.claude`
  configuration are out of scope.
