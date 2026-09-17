---
name: deps-audit
description: Runs the CI dependency audit locally with the repo's package manager and resolves advisories the repo way — exact-pinned bumps for direct dependencies first, an override/resolution pin for transitives — then re-audits and re-verifies. Use only when the user asks to audit dependencies or to fix a security advisory reported by CI.
disable-model-invocation: true
---
Resolve the package manager:

```bash
PM="$(jq -r '.packageManager // empty' .claude/conventions.json 2>/dev/null)"
```

Empty → detect from the lockfile at the repo root: `pnpm-lock.yaml` → pnpm, `package-lock.json` → npm, `yarn.lock` → yarn, `bun.lockb` / `bun.lock` → bun. Two lockfiles or none → stop and ask.

| | pnpm | npm | yarn (≥ 2) | bun |
|---|---|---|---|---|
| blocker audit (runtime deps, high+) | `pnpm audit --prod --audit-level high` | `npm audit --omit=dev --audit-level=high` | `yarn npm audit -AR --environment production --severity high` | `bun audit --audit-level=high` |
| warning audit (all deps, moderate+) | `pnpm audit --audit-level moderate` | `npm audit --audit-level=moderate` | `yarn npm audit -AR --severity moderate` | `bun audit --audit-level=moderate` |
| machine-readable report | `pnpm audit --json` | `npm audit --json` | `yarn npm audit -AR --json` | `bun audit --json` |
| latest stable of a package | `pnpm view <pkg> version` | `npm view <pkg> version` | `yarn npm info <pkg> --fields version --json` | `bun info <pkg> version` |
| exact-pinned bump (direct dep) | `pnpm add -E <pkg>@<v>` | `npm install --save-exact <pkg>@<v>` | `yarn add --exact <pkg>@<v>` | `bun add --exact <pkg>@<v>` |
| transitive pin location | `pnpm-workspace.yaml#overrides` (no workspace file → `package.json#pnpm.overrides`) | `package.json#overrides` | `package.json#resolutions` | `package.json#overrides` |
| reinstall | `pnpm install` | `npm install` | `yarn install` | `bun install` |

Yarn 1 (classic) differs: `yarn audit --groups dependencies --level high`, `yarn info <pkg> version`, pins in `package.json#resolutions`.

1. Run the blocker audit (what CI fails on) and the warning audit; capture the machine-readable report.
2. For each advisory, in this order:
   - direct dependency (listed in a `package.json` of the repo) → find the latest stable on the registry and bump it exact-pinned in the owning app/workspace (run the bump from that directory, or with the package manager's workspace filter). Prefer this over any pin.
   - transitive only → add `"<pkg>@<vulnerable-range>": "<fixed-version>"` at the transitive pin location, following the existing entries' shape and comment style; `resolutions` takes the bare `<pkg>` key. A pin is temporary: note the parent that must catch up so the entry can be dropped later.
   - Never hand-edit a manifest for a bump; only the pin location is edited by hand.
3. Reinstall, then re-run both audits.
4. Run `/conventions:verify-app all` if any runtime dependency changed.
5. Report: table advisory → package → fix (bump / pin) → verified (audit re-run clean, verify-app result). Do not commit.
