#!/usr/bin/env bash
# PreToolUse(Bash): dependencies are exact-pinned. Blocks "<pm> add <pkg>"
# (npm: install / i / add; bun: add / install) unless the package manager's
# exact flag is given or every package token carries "@<version>".
# Package manager: .claude/conventions.json#packageManager, else the lockfile
# (lib.sh#detect_pm). Undetected or ambiguous → warning on stderr, exit 0.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

event="$(cat)"
if [ "$(jq -r '.tool_name // ""' <<<"$event")" != "Bash" ]; then
  exit 0
fi
cmd="$(jq -r '.tool_input.command // ""' <<<"$event")"
HOOK_CWD="$(jq -r '.cwd // ""' <<<"$event")"

if ! in_git_repo; then
  exit 0
fi

# Per package manager: the subcommands that add a package, and the flags that
# pin it exactly (the first one is the one suggested).
add_subcommands() {
  case "$1" in
    pnpm) printf 'add' ;;
    npm) printf 'install|i|add' ;;
    yarn) printf 'add' ;;
    bun) printf 'add|install' ;;
  esac
}

exact_flags() {
  case "$1" in
    pnpm) printf -- '-E|--save-exact' ;;
    npm) printf -- '--save-exact|-E' ;;
    yarn) printf -- '--exact|-E' ;;
    bun) printf -- '--exact|-E' ;;
  esac
}

# Collect the segments that look like "<known pm> <add-like subcommand> …"
# before resolving the package manager, so unrelated commands never warn.
candidates=()
while IFS= read -r line; do
  seg="$(normalize_segment "$line")"
  if [[ "$seg" =~ ^(pnpm|npm|yarn|bun)[[:space:]]+(add|install|i)([[:space:]]|$) ]]; then
    candidates+=("$seg")
  fi
done < <(split_segments "$cmd")

if [ "${#candidates[@]}" -eq 0 ]; then
  exit 0
fi

pm="$(conv_get packageManager "")"
if [ -z "$pm" ]; then
  pm="$(detect_pm)"
fi
if [ -z "$pm" ]; then
  conv_warn deps-exact "package manager not detected (no or ambiguous lockfile) — set packageManager in .claude/conventions.json; check skipped"
  exit 0
fi

subs="$(add_subcommands "$pm")"
flags="$(exact_flags "$pm")"
suggested="${flags%%|*}"

for seg in "${candidates[@]}"; do
  if ! [[ "$seg" =~ ^${pm}[[:space:]]+($subs)([[:space:]]+(.*))?$ ]]; then
    continue
  fi
  sub="${BASH_REMATCH[1]}"
  after="${BASH_REMATCH[3]:-}"
  if [[ " $after " =~ [[:space:]]($flags)[[:space:]] ]]; then
    continue
  fi
  unpinned=()
  for tok in $after; do
    if [[ "$tok" == -* ]]; then
      continue
    fi
    body="${tok#@}" # drop the scope marker so "@types/node@1.0.0" keeps one "@"
    if [[ "$body" != *"@"* ]]; then
      unpinned+=("$tok")
    fi
  done
  if [ "${#unpinned[@]}" -eq 0 ]; then
    continue
  fi
  corrected="$pm $sub $suggested"
  if [ -n "$after" ]; then
    corrected="$corrected $after"
  fi
  conv_warn deps-exact "pin versions exactly (${unpinned[*]}): use \"$corrected\" or \"<pkg>@<x.y.z>\" — check the registry for the latest stable first"
  exit 2
done
exit 0
