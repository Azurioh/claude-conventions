# Implementation Plan: Claude Conventions Plugin

**Branch**: `001-claude-conventions-plugin` | **Date**: 2026-09-17 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-claude-conventions-plugin/spec.md`

## Summary

Extract the project-agnostic layer of `bsk-apps/.claude` into a Claude Code plugin
marketplace: five bash hooks parameterised by a per-repo `.claude/conventions.json`
(auto-detected package manager / formatter, default size cap, mandatory integration
branch), six generic skills and four generic agents rewritten without bsk references, a
`port-claude-config` skill that discovers a target repo and writes the rule templates
(sentinel-delimited sections so a refresh never touches project-owned content), a bash test
harness over three fixture repos, and a ccprofile profile for one-command install.
Research decisions: [research.md](research.md). Contracts: [contracts/](contracts/).

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default) for hooks and tests; Markdown for skills,
agents, templates; JSON manifests.

**Primary Dependencies**: `jq` (stdin parsing, conventions file), `git`, `gh` (PR skills),
`shellcheck` (lint), Claude Code CLI ≥ current (`claude plugin validate`, marketplace
commands), `ccprofile` (distribution).

**Storage**: files only — plugin in the repo, per-repo `.claude/conventions.json`.

**Testing**: `tests/run.sh` (bash assertions over fixture repos in temp dirs), `shellcheck`,
`claude plugin validate`. CI: GitHub Actions running shellcheck + `tests/run.sh`.

**Target Platform**: macOS and Linux shells; consuming repos are JS/TS with a lockfile.

**Project Type**: Claude Code plugin marketplace (single plugin) + test harness.

**Performance Goals**: each PreToolUse hook completes < 1 s on a typical repo (`pr-size.sh`
< 5 s on a 400-line diff); SessionStart hook < 1 s.

**Constraints**: hooks fail open on missing configuration; no dependency beyond `jq`/`git`/
`gh`; hooks shellcheck-clean; no bsk-apps identifiers anywhere in `plugins/`.

**Scale/Scope**: 5 hooks, 7 skills, 4 agents, 9 templates, 3 fixtures, ~15 test assertions
per fixture; a handful of consuming repos.

## Constitution Check

`.specify/memory/constitution.md` is the unfilled template (no project principles defined);
no gates apply. Standing rules from the user's global configuration that act as gates here:
every shell script `shellcheck`-clean; no placeholders/TODOs in delivered files; latest
tool versions verified, not assumed; no commit without the user's OK. All satisfied by the
design; re-checked after Phase 1 — no violation.

## Project Structure

### Documentation (this feature)

```text
specs/001-claude-conventions-plugin/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (conventions-json, hooks, templates)
└── tasks.md             # Phase 2 output (/speckit-tasks — not created by /speckit-plan)
```

### Source Code (repository root)

```text
.claude-plugin/
└── marketplace.json                 # name: claude-conventions, plugin: ./plugins/conventions
plugins/conventions/
├── .claude-plugin/plugin.json
├── hooks/
│   ├── hooks.json                   # PreToolUse Bash ×3, PostToolUse Edit|Write, SessionStart
│   ├── lib.sh                       # segment parsing (from reference) + conv_get + detectors
│   ├── guard-git.sh
│   ├── deps-exact.sh
│   ├── pr-size.sh
│   ├── format.sh
│   └── branch-info.sh
├── skills/
│   ├── pr/SKILL.md
│   ├── verify-app/SKILL.md
│   ├── test-gaps/SKILL.md
│   ├── adr/SKILL.md
│   ├── release/SKILL.md
│   ├── deps-audit/SKILL.md
│   └── port-claude-config/
│       ├── SKILL.md                 # discover → mapping table → confirm → write | --refresh
│       ├── scripts/
│       │   ├── discover.sh          # prints repo facts as JSON (lockfile, formatter, CI, branches, apps)
│       │   ├── render.sh            # resolves {{PLACEHOLDERS}} from conventions.json
│       │   └── refresh.sh           # replaces sentinel sections in place
│       └── templates/
│           ├── CLAUDE.md
│           ├── rules/{workflow,architecture,knowledge,pitfalls,commands}.md
│           ├── settings.json
│           ├── conventions.json
│           └── gitignore
└── agents/
    ├── ci-triage.md
    ├── rules-reviewer.md
    ├── test-writer.md
    └── repo-explorer.md
schema/conventions.schema.json       # editor validation for .claude/conventions.json
profiles/conventions.json            # ccprofile profile → symlink into ~/.claude/profiles/
tests/
├── run.sh                           # fixtures × hooks assertions
└── fixtures/
    ├── pnpm-biome/                  # package.json, pnpm-lock.yaml, biome.json, .claude/conventions.json
    ├── npm-prettier/                # package.json, package-lock.json, .prettierrc, .claude/conventions.json
    └── no-conventions/              # package.json, pnpm-lock.yaml
.github/workflows/ci.yml             # shellcheck + tests/run.sh
README.md
```

**Structure Decision**: single plugin under `plugins/conventions/` so the marketplace can
grow (a second plugin later) without moving files; templates and helper scripts live inside
the `port-claude-config` skill so the skill resolves them relative to its own directory;
tests and schema are repository-level because they are not shipped to consumers.

## Implementation phases (input for /speckit-tasks)

1. **Scaffold + manifests**: `marketplace.json`, `plugin.json`, `hooks.json`, empty dirs,
   `claude plugin validate` green on the skeleton, CI workflow.
2. **Hooks**: port `lib.sh` (segment helpers) and add `conv_get`, `detect_pm`,
   `detect_formatter`, `project_root`; port each hook against `contracts/hooks.md`;
   fixtures + `tests/run.sh` written first (red), then hooks (green); shellcheck.
3. **Skills**: rewrite the six generic skills per research R6; `port-claude-config` with its
   three scripts and templates (`contracts/templates.md`), including `--refresh`.
4. **Agents**: rewrite the four agents per R6 (skill references namespaced
   `/conventions:<skill>`).
5. **Distribution**: `schema/conventions.schema.json`, `profiles/conventions.json`, README
   (install / per-project setup / value resolution / update), quickstart walkthrough on the
   `pnpm-biome` fixture end-to-end.

## Complexity Tracking

No constitution violations to justify.
