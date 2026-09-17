---
name: adr
description: Writes a new Architecture Decision Record (next number, NNNN-<slug>.md) in the ADR directory from .claude/conventions.json#adrDir (default docs/adr) for a long-term choice made during development. Use when a task introduces a new dependency category, storage format, protocol between apps, ownership boundary, or anything a future dev would ask "why?" about — before opening the PR that carries the change.
argument-hint: "<short decision title>"
---
Create `<adrDir>/NNNN-<kebab-slug>.md` for the decision "$ARGUMENTS".

1. Resolve the directory and next number:
   ```bash
   ADR_DIR="$(jq -r '.adrDir // "docs/adr"' .claude/conventions.json 2>/dev/null || echo docs/adr)"
   mkdir -p "$ADR_DIR" && ls "$ADR_DIR"
   ```
   NNNN = highest existing `NNNN-*.md` number + 1 (0001 when the directory is empty), zero-padded to 4 digits. Slug = the title in kebab-case, ≤ 6 words.
2. Structure: when the directory already has ADRs, copy the section structure of the most recent one (it may carry extra sections — keep them). Otherwise use this template verbatim:
   ```markdown
   # NNNN — <Title>

   - **Status**: proposed
   - **Date**: YYYY-MM-DD

   ## Context

   What situation or constraint forced a decision. Which apps and files are involved.

   ## Decision

   What was decided, in one paragraph. Then the alternatives considered, each with the reason it was rejected.

   ## Consequences

   What becomes easier. What becomes harder or is now forbidden. Follow-ups this creates.
   ```
   Status `proposed` unless the user says `accepted`. Date = today (ISO).
3. Fill every section from the conversation: what was decided, the alternatives rejected and why, what becomes harder. Name the apps (keys of `.claude/conventions.json#apps`, when present) and files affected. No placeholders.
4. If an existing ADR is superseded, add `Superseded by NNNN` to its Status line.
5. Show the file path and a 3-line summary; do not commit.
