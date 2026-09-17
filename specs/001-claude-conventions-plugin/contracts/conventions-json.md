# Contract: `.claude/conventions.json`

```json
{
  "$schema": "https://raw.githubusercontent.com/Azurioh/claude-conventions/main/schema/conventions.schema.json",
  "integrationBranch": "demo",
  "productionBranch": "main",
  "packageManager": "pnpm",
  "formatter": "biome",
  "prSize": { "lines": 400, "files": 15, "exclude": ["**/pnpm-lock.yaml", "**/migrations/**"], "label": "large-pr" },
  "apps": { "hub": "apps/hub", "bot": "apps/discord-bot" },
  "adrDir": "docs/adr"
}
```

- Only `integrationBranch` is required. Every other key overrides a detected/default value.
- The JSON schema is published at `schema/conventions.schema.json` in the repository and
  referenced by `$schema` for editor validation; hooks do not validate against it (jq only).
- Readers: all hooks (via `lib.sh#conv_get`), skills `pr`, `verify-app`, `test-gaps`,
  `release`, `deps-audit`, `adr`, agents `ci-triage`, `repo-explorer`.
- Writer: `port-claude-config` (creates; refresh never rewrites it).
