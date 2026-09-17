#!/usr/bin/env bash
# SessionStart: print the current branch and its upstream state on stdout
# (session context); warn when sitting on a protected branch (the integration
# branch from .claude/conventions.json and the production branch). Also reports
# a missing, unparsable or inconsistent conventions file. Never blocks.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

event="$(cat)"
HOOK_CWD="$(jq -r '.cwd // ""' <<<"$event")"
cwd="${HOOK_CWD:-.}"

if ! in_git_repo; then
  exit 0
fi

branch="$(git -C "$cwd" symbolic-ref --short -q HEAD || printf 'detached')"
printf 'git branch: %s\n' "$branch"

if upstream="$(git -C "$cwd" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
  counts="$(git -C "$cwd" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null || printf '0\t0')"
  behind="${counts%%[[:space:]]*}"
  ahead="${counts##*[[:space:]]}"
  printf 'upstream: %s (ahead %s, behind %s)\n' "$upstream" "$ahead" "$behind"
else
  printf 'upstream: none\n'
fi

file="$(conv_file)"
integration=""
if [ ! -f "$file" ]; then
  printf 'conventions: no .claude/conventions.json — run /conventions:port-claude-config to create it (hooks skip their branch checks until then)\n'
elif ! jq -e . "$file" >/dev/null 2>&1; then
  printf 'conventions: .claude/conventions.json is not valid JSON — fix it (hooks fail open until then)\n'
else
  integration="$(conv_get integrationBranch "")"
  if [ -z "$integration" ]; then
    printf 'conventions: .claude/conventions.json has no integrationBranch — add it or run /conventions:port-claude-config\n'
  fi
fi
production="$(production_branch)"
if [ -n "$integration" ] && [ "$integration" = "$production" ]; then
  printf "conventions: integrationBranch and productionBranch are both '%s' — they must differ; fix .claude/conventions.json\\n" "$integration"
fi

if [ -n "$integration" ] && [ "$branch" = "$integration" ]; then
  printf 'WARNING: on %s — create a feature branch first: git pull && git switch -c feat/<name>\n' "$branch"
elif [ "$branch" = "$production" ]; then
  if [ -n "$integration" ]; then
    printf 'WARNING: on %s — branch off %s first: git switch %s && git pull && git switch -c feat/<name>\n' "$branch" "$integration" "$integration"
  else
    printf 'WARNING: on %s — create a feature branch first: git switch -c feat/<name>\n' "$branch"
  fi
fi
exit 0
