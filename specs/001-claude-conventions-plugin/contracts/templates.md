# Contract: rule templates and refresh

Location: `plugins/conventions/skills/port-claude-config/templates/`
(`CLAUDE.md`, `rules/workflow.md`, `rules/architecture.md`, `rules/knowledge.md`,
`rules/pitfalls.md`, `rules/commands.md` (per-app sheet skeleton), `settings.json`,
`conventions.json`, `gitignore`).

Placeholders (resolved once at port time): `{{INTEGRATION_BRANCH}}`, `{{PRODUCTION_BRANCH}}`,
`{{PKG_MANAGER}}`, `{{PKG_EXACT_FLAG}}`, `{{FORMATTER}}`, `{{PR_SIZE_LINES}}`,
`{{PR_SIZE_FILES}}`, `{{PR_SIZE_LABEL}}`, `{{APP_TABLE}}`, `{{ADR_DIR}}`,
`{{DEPLOY_NOTE}}`.

Sections: generic content is wrapped as

```
<!-- conventions:begin workflow.branches -->
…
<!-- conventions:end workflow.branches -->
```

Refresh (`/conventions:port-claude-config --refresh`): for each template file that exists
in the target, replace the body of every matching sentinel pair with the freshly resolved
template body (placeholders resolved from the current `conventions.json`); leave everything
else byte-identical; append missing sections at the end with a one-line notice; never touch
files that contain no sentinel; never touch `conventions.json`, `settings.json`,
`pitfalls.md` entries, or `rules/<app>/`.
