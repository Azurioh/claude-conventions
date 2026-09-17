#!/usr/bin/env bash
# PostToolUse(Edit|Write): format the touched file with the repo's formatter.
# Formatter: .claude/conventions.json#formatter, else lib.sh#detect_formatter
# (biome / prettier / none). Runs "biome check --write <file>" or "prettier
# --write <file>" through <root>/node_modules/.bin/<formatter> when the
# formatter is installed there (executed directly: "<pm> exec" is not portable —
# bun does not resolve .bin through exec), else the formatter on PATH; skips
# silently when neither exists. Never blocks: exit 0 always, stderr only when
# the formatter itself fails.
set -uo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

event="$(cat)"
file="$(jq -r '.tool_input.file_path // ""' <<<"$event")"
HOOK_CWD="$(jq -r '.cwd // ""' <<<"$event")"

if [ -z "$file" ] || [ ! -f "$file" ] || ! in_git_repo; then
  exit 0
fi
case "$file" in
  *.ts | *.tsx | *.js | *.mjs | *.cjs | *.json | *.css) ;;
  *) exit 0 ;;
esac

root="$(project_root)"
formatter="$(conv_get formatter "")"
if [ -z "$formatter" ]; then
  formatter="$(detect_formatter "$root")"
fi
case "$formatter" in
  biome) args=(check --write "$file") ;;
  prettier) args=(--write "$file") ;;
  *) exit 0 ;;
esac

if [ -x "$root/node_modules/.bin/$formatter" ]; then
  runner=("$root/node_modules/.bin/$formatter")
elif command -v "$formatter" >/dev/null 2>&1; then
  runner=("$formatter")
else
  exit 0 # formatter configured but not installed: nothing to run
fi

# The formatter's own config decides what it ignores (generated code, vendored UI).
if ! (cd "$root" && "${runner[@]}" "${args[@]}" >/dev/null 2>&1); then
  conv_warn format "$formatter failed on ${file#"$root"/} — run \"${runner[0]#"$root"/} ${args[*]}\" to see why"
fi
exit 0
