# Contract: rule templates and refresh

Location: `plugins/conventions/rules/` (`CLAUDE.md`, `workflow.md`, `architecture.md`,
`coding.md`, `knowledge.md`, `pitfalls.md`, `commands.md` (per-app sheet skeleton),
`_project/settings.json`, `_project/conventions.json`, `_project/gitignore`) — moved in
0.3.0 from `skills/port-claude-config/templates/` so the rules are visible at the top of
the plugin; `CLAUDE.md` targets `CLAUDE.md`, every other `<name>.md` targets
`.claude/rules/<name>.md`.

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
