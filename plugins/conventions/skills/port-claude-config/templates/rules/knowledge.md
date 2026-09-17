# Capturing knowledge while working

<!-- conventions:begin knowledge.adr -->
- **Long-term choice made during a task** (new dependency category, storage
  format, ownership boundary, protocol between apps, anything a future dev
  would ask "why?" about) → run `/conventions:adr` before opening the PR.
  ADRs live in `{{ADR_DIR}}/NNNN-<slug>.md`; the most recent one is the model.
<!-- conventions:end knowledge.adr -->

<!-- conventions:begin knowledge.pitfalls -->
- **Same error hit twice, or a trap that cost more than a few minutes and is
  not obvious from the code** → append an entry to `.claude/rules/pitfalls.md`
  in the same PR: `- YYYY-MM-DD — <symptom> → <cause> → <fix>` (≤ 3 lines).
- Keep `pitfalls.md` under 40 lines: when an entry is stable and app-specific,
  move it into that app's rule file and delete it from pitfalls.
- Do not record: linter/type errors, one-off typos, things the tests already
  explain.
<!-- conventions:end knowledge.pitfalls -->
