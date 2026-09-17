#!/usr/bin/env bash
# PreToolUse(Bash): keep PRs reviewable. On "gh pr create --base <b>", counts the
# diff <b>...<h> minus the excluded globs and blocks when it exceeds the caps
# unless the escape-hatch label is passed. <h> is the explicit --head/-H value
# when given (local branch, else origin/<h>), falling back to HEAD otherwise.
# Values (.claude/conventions.json, with defaults): prSize.lines (400),
# prSize.files (15), prSize.label (large-pr), prSize.exclude (lockfiles,
# **/migrations/**, **/components/ui/**). The release pair
# (--base <production> --head <integration>) is exempt.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

event="$(cat)"
if [ "$(jq -r '.tool_name // ""' <<<"$event")" != "Bash" ]; then
  exit 0
fi
cmd="$(jq -r '.tool_input.command // ""' <<<"$event")"
HOOK_CWD="$(jq -r '.cwd // ""' <<<"$event")"
cwd="${HOOK_CWD:-.}"

if ! in_git_repo; then
  exit 0
fi

create_seg=""
while IFS= read -r line; do
  seg="$(normalize_segment "$line")"
  if [ -z "$create_seg" ] && [[ "$seg" =~ ^gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]]; then
    create_seg="$seg"
  fi
done < <(split_segments "$cmd")

if [ -z "$create_seg" ]; then
  exit 0
fi

max_lines="$(conv_get prSize.lines 400)"
max_files="$(conv_get prSize.files 15)"
label="$(conv_get prSize.label large-pr)"
excludes=()
while IFS= read -r pattern; do
  if [ -n "$pattern" ]; then
    excludes+=("$pattern")
  fi
done < <(conv_get prSize.exclude "")
if [ "${#excludes[@]}" -eq 0 ]; then
  excludes=('**/pnpm-lock.yaml' '**/package-lock.json' '**/yarn.lock' '**/migrations/**' '**/components/ui/**')
fi
integration="$(conv_get integrationBranch "")"
production="$(production_branch)"

# has_label <seg> — true when any --label/-l value carries the escape-hatch label.
has_label() {
  local rest="$1" val
  while [[ "$rest" =~ (--label|-l)([[:space:]]+|=)?([^[:space:]]+)(.*)$ ]]; do
    val="$(strip_quotes "${BASH_REMATCH[3]}")"
    rest="${BASH_REMATCH[4]}"
    if [[ ",$val," == *",$label,"* ]]; then
      return 0
    fi
  done
  return 1
}

# excluded <path> — true when <path> matches one of the exclusion globs. A
# leading "**/" means "at any depth, including the root"; inside a pattern, "*"
# and "**" both match across directory separators (bash case semantics).
excluded() {
  local path="$1" pattern
  for pattern in "${excludes[@]}"; do
    case "$pattern" in
      '**/'*)
        pattern="${pattern#\*\*/}"
        # shellcheck disable=SC2254  # the pattern must stay unquoted to glob
        case "$path" in
          $pattern | */$pattern) return 0 ;;
        esac
        ;;
      *)
        # shellcheck disable=SC2254
        case "$path" in
          $pattern) return 0 ;;
        esac
        ;;
    esac
  done
  return 1
}

base="$(flag_value_last "$create_seg" '--base|-B')"
head_ref="$(flag_value_last "$create_seg" '--head|-H')"

if [ -n "$integration" ] && [ "$base" = "$production" ] && [ "$head_ref" = "$integration" ]; then
  exit 0 # the release PR is deliberately large
fi
if has_label "$create_seg"; then
  exit 0
fi
if [ -z "$base" ]; then
  exit 0 # guard-git rejects a missing base
fi

top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$top" ]; then
  exit 0 # not a work tree: nothing to measure
fi

git -C "$top" fetch -q origin "$base" >/dev/null 2>&1 || true

ref="$base"
if git -C "$top" rev-parse -q --verify "origin/$base" >/dev/null 2>&1; then
  ref="origin/$base"
elif ! git -C "$top" rev-parse -q --verify "$base" >/dev/null 2>&1; then
  exit 0 # unknown base locally: nothing to measure
fi

head_effective="HEAD"
if [ -n "$head_ref" ]; then
  git -C "$top" fetch -q origin "$head_ref" >/dev/null 2>&1 || true
  if git -C "$top" rev-parse -q --verify "$head_ref" >/dev/null 2>&1; then
    head_effective="$head_ref"
  elif git -C "$top" rev-parse -q --verify "origin/$head_ref" >/dev/null 2>&1; then
    head_effective="origin/$head_ref"
  else
    exit 0 # unknown head: nothing to measure
  fi
fi

files=0
lines=0
while IFS=$'\t' read -r added deleted path; do
  if [ -z "$path" ] || excluded "$path"; then
    continue
  fi
  files=$((files + 1))
  if [ "$added" != "-" ]; then
    lines=$((lines + added))
  fi
  if [ "$deleted" != "-" ]; then
    lines=$((lines + deleted))
  fi
done < <(git -C "$top" diff --numstat "$ref...$head_effective")

if [ "$files" -gt "$max_files" ] || [ "$lines" -gt "$max_lines" ]; then
  conv_warn pr-size "$lines changed lines / $files files vs $base (cap $max_lines lines, $max_files files). Split into a stack of smaller PRs, or pass --label $label deliberately."
  exit 2
fi
exit 0
