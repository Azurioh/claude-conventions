#!/usr/bin/env bash
# PostToolUse(Edit|Write): keep AGENTS.md in sync with the Claude rules. When
# the touched file is the repo-root CLAUDE.md or a .claude/rules/**/*.md, and
# the repo's AGENTS.md exists with the GENERATED header (opt-in by presence),
# reruns scripts/agents-md.sh quietly. A missing or hand-written AGENTS.md is
# never created or touched. Never blocks: exit 0 always; stderr carries the
# generator's own warning (oversize) or one line when it fails.
set -uo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

event="$(cat)"
file="$(jq -r '.tool_input.file_path // ""' <<<"$event")"

if [ -z "$file" ] || [ ! -f "$file" ]; then
  exit 0
fi
dir="$(cd "$(dirname "$file")" && pwd -P)" || exit 0
if ! in_git_repo "$dir"; then
  exit 0
fi
root="$(git -C "$dir" rev-parse --show-toplevel)"
rel="$dir/$(basename "$file")"
rel="${rel#"$root/"}"
case "$rel" in
  CLAUDE.md | .claude/rules/*.md) ;;
  *) exit 0 ;;
esac
if [ ! -f "$root/AGENTS.md" ] || ! agents_md_generated "$root/AGENTS.md"; then
  exit 0
fi

if ! err="$("$(dirname "${BASH_SOURCE[0]}")/../scripts/agents-md.sh" --repo "$root" 2>&1 >/dev/null)"; then
  conv_warn agents-md "regeneration failed — run \"agents-md.sh --repo $root\" to see why: ${err%%$'\n'*}"
  exit 0
fi
if [ -n "$err" ]; then
  printf '%s\n' "$err" >&2
fi
exit 0
