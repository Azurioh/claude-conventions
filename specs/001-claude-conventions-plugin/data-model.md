# Data Model: Claude Conventions Plugin

## Plugin (repository-owned)

| Field | Where | Notes |
|---|---|---|
| marketplace name | `.claude-plugin/marketplace.json#name` | `claude-conventions`; part of the install id |
| plugin name / version | `plugins/conventions/.claude-plugin/plugin.json` | `conventions`; semver, bumped per release |
| hooks | `plugins/conventions/hooks/hooks.json` + `hooks/*.sh` | see `contracts/hooks.md` |
| skills | `plugins/conventions/skills/<name>/SKILL.md` | `pr`, `verify-app`, `test-gaps`, `adr`, `release`, `deps-audit`, `port-claude-config` |
| agents | `plugins/conventions/agents/<name>.md` | `ci-triage`, `rules-reviewer`, `test-writer`, `repo-explorer` |
| templates | `plugins/conventions/skills/port-claude-config/templates/` | see `contracts/templates.md` |
| profile | `profiles/conventions.json` | ccprofile profile referencing the plugin |

## Conventions file (project-owned) — `.claude/conventions.json`

| Key | Type | Required | Default / detection |
|---|---|---|---|
| `integrationBranch` | string | yes | — (hooks warn + skip when absent) |
| `productionBranch` | string | no | `origin/HEAD` target, fallback `main` |
| `packageManager` | `pnpm\|npm\|yarn\|bun` | no | from lockfile; ambiguous → unset |
| `formatter` | `biome\|prettier\|none` | no | from config files; none found → `none` |
| `prSize.lines` | integer | no | 400 |
| `prSize.files` | integer | no | 15 |
| `prSize.exclude` | string[] (globs) | no | lockfiles, `**/migrations/**`, `**/components/ui/**` |
| `prSize.label` | string | no | `large-pr` |
| `apps` | object `name → path` | no | absent = single-app repo |
| `adrDir` | string | no | `docs/adr` |

Validation: unknown keys are ignored silently (the schema documents them); wrong types fall back to the default
with a warning; `integrationBranch == productionBranch` is reported by the session hook
(never blocks; hooks still fail open).

## Target repo config (produced by `port-claude-config`)

| Artifact | Path | Owner after port |
|---|---|---|
| project memory | `CLAUDE.md` | template-owned sections + project app table |
| generic rules | `.claude/rules/{workflow,architecture,knowledge,pitfalls}.md` | template-owned sections; pitfalls entries project-owned |
| app command sheets | `.claude/rules/<app>/commands.md` or `.claude/rules/commands.md` | project |
| settings | `.claude/settings.json` | project (seeded: permissions, deny force-push, `enabledPlugins: {}`, no hooks — hooks come from the plugin) |
| conventions | `.claude/conventions.json` | project |
| gitignore | `.gitignore` (`.claude/*` + `!` negations) | project |

State transitions of a target repo: `untooled → installed (plugin only) → ported (rules +
conventions) → refreshed (template sections updated)`. `installed` is reachable without
`ported` (hooks warn until `conventions.json` exists).
