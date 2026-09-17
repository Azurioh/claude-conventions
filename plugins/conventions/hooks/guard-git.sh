#!/usr/bin/env bash
# PreToolUse(Bash) guard for the branch model and shared worktrees. Protected
# branches are the integration branch (.claude/conventions.json, required) and
# the production branch (override, else origin/HEAD, else main).
# Blocks (exit 2 + one reason line on stderr):
#   - gh pr create without --base, or with --base <production> unless it is the
#     release pair (--base <production> --head <integration>)
#   - git push (forced or not) whose target is a protected branch
#   - git commit / git push while checked out on a protected branch
#   - bare "git stash" and "git stash pop" (stash stack is shared across worktrees)
# Fails open: not a git work tree or no conventions file → exit 0.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

event="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$event")"
if [ "$tool" != "Bash" ]; then
  exit 0
fi
cmd="$(jq -r '.tool_input.command // ""' <<<"$event")"
HOOK_CWD="$(jq -r '.cwd // ""' <<<"$event")"
cwd="$HOOK_CWD"

if ! in_git_repo; then
  exit 0
fi

deny() {
  conv_warn guard-git "$1"
  exit 2
}

# Resolved lazily so a command without git/gh segments never warns about a
# missing conventions file.
INTEGRATION=""
PRODUCTION=""
BRANCHES_STATE=""

# resolve_branches — fills INTEGRATION / PRODUCTION once; returns 1 (after the
# lib.sh warning) when the integration branch is not configured.
resolve_branches() {
  if [ -z "$BRANCHES_STATE" ]; then
    if INTEGRATION="$(conv_require integrationBranch guard-git)"; then
      PRODUCTION="$(production_branch)"
      BRANCHES_STATE="ok"
    else
      BRANCHES_STATE="missing"
    fi
  fi
  [ "$BRANCHES_STATE" = "ok" ]
}

# is_protected <branch> — true when <branch> is the integration or production branch.
is_protected() {
  [ -n "$1" ] && { [ "$1" = "$INTEGRATION" ] || [ "$1" = "$PRODUCTION" ]; }
}

# branch_of <dir> — prints the checked-out branch of <dir>, empty when unknown.
branch_of() {
  local dir="$1"
  if [ -z "$dir" ] || ! in_git_repo "$dir"; then
    return 0
  fi
  git -C "$dir" symbolic-ref --short -q HEAD || true
}

# push_target_protected <gitseg> — prints the first refspec destination of
# "git push …" that is a protected branch ("<branch>", "<src>:<branch>",
# "+<branch>" or "refs/heads/<branch>"); returns 1 when there is none.
push_target_protected() {
  local rest="${1#git push}" tok dest
  for tok in $rest; do
    case "$tok" in
      -*) continue ;;
    esac
    dest="${tok#+}"
    dest="${dest##*:}"
    dest="${dest#refs/heads/}"
    if is_protected "$dest"; then
      printf '%s' "$dest"
      return 0
    fi
  done
  return 1
}

# is_force_push <gitseg> — true when the push carries -f / --force / --force-with-lease.
is_force_push() {
  [[ "$1" =~ [[:space:]](-[A-Za-z]*f[A-Za-z]*|--force|--force-with-lease(=[^[:space:]]*)?)([[:space:]]|$) ]]
}

# Evaluate each shell segment separately so "<pm> test && git stash" is caught.
segments=()
while IFS= read -r line; do
  segments+=("$line")
done < <(split_segments "$cmd")

for raw in ${segments[@]+"${segments[@]}"}; do
  seg="$(normalize_segment "$raw")"
  if [ -z "$seg" ]; then
    continue
  fi

  if [[ "$seg" =~ ^gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]]; then
    if ! resolve_branches; then
      continue
    fi
    base="$(flag_value_last "$seg" '--base|-B')"
    head_ref="$(flag_value_last "$seg" '--head|-H')"
    if [ -z "$base" ]; then
      deny "always pass --base: $INTEGRATION for a normal PR, the previous stack branch for a stacked PR (release PRs: --base $PRODUCTION --head $INTEGRATION)"
    fi
    if [ "$base" = "$PRODUCTION" ] && [ "$head_ref" != "$INTEGRATION" ]; then
      deny "$PRODUCTION only receives the release PR from $INTEGRATION (--base $PRODUCTION --head $INTEGRATION). Use --base $INTEGRATION."
    fi
  fi

  # Read through the globals, not a command substitution: GIT_C_PATH would be
  # lost in the subshell.
  git_strip_opts "$seg" >/dev/null
  gitseg="$GIT_SEG"

  if [[ "$gitseg" =~ ^git[[:space:]]+stash([[:space:]]+pop([[:space:]]|$)|[[:space:]]*$) ]]; then
    deny "stash stack is shared across worktrees. Use: git stash push -u -m <tag>; git stash list --format='%H %gs'; git stash apply <sha>"
  fi

  if ! [[ "$gitseg" =~ ^git[[:space:]]+(push|commit)([[:space:]]|$) ]]; then
    continue
  fi
  if ! resolve_branches; then
    continue
  fi

  seg_dir="$cwd"
  if [ -n "$GIT_C_PATH" ]; then
    case "$GIT_C_PATH" in
      /*) seg_dir="$GIT_C_PATH" ;;
      *) seg_dir="$cwd/$GIT_C_PATH" ;;
    esac
  fi
  branch="$(branch_of "$seg_dir")"

  if [[ "$gitseg" =~ ^git[[:space:]]+push([[:space:]]|$) ]]; then
    kind="direct"
    if is_force_push "$gitseg"; then
      kind="force"
    fi
    if target="$(push_target_protected "$gitseg")"; then
      deny "$kind push to '$target' is forbidden; open a PR against $INTEGRATION."
    fi
    if is_protected "$branch"; then
      deny "you are on '$branch'; branch off $INTEGRATION first: git switch -c feat/<name>"
    fi
  fi

  if [[ "$gitseg" =~ ^git[[:space:]]+commit([[:space:]]|$) ]] && is_protected "$branch"; then
    deny "no commits on '$branch'; branch off $INTEGRATION first: git switch -c feat/<name>"
  fi
done

exit 0
