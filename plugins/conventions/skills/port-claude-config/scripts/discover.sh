#!/usr/bin/env bash
# discover.sh [root] — prints one JSON object describing the target repository
# for the port-claude-config skill: package manager, formatter, lockfiles,
# workspaces, app guess, branches, CI workflows (jobs and their run: lines),
# existing Claude config and whether .gitignore already mentions .claude.
# Read-only. bash + jq; yq (mikefarah v4) is used for YAML when present, with
# a conservative awk fallback otherwise (the "ciParser" key says which ran;
# DISCOVER_YQ=0 forces the fallback so the tests can cover it).
# <root> defaults to $CLAUDE_PROJECT_DIR, then the git toplevel, then the cwd.
set -euo pipefail

# shellcheck source=../../../hooks/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib.sh"

if ! command -v jq >/dev/null 2>&1; then
  printf 'discover: jq is required\n' >&2
  exit 1
fi

root="${1:-$(project_root)}"
root="$(cd "$root" && pwd)"

# ---------------------------------------------------------------------------
# Package manager, formatter, lockfiles
# ---------------------------------------------------------------------------

pm="$(detect_pm "$root")"
if [ -z "$pm" ] && [ -f "$root/package.json" ]; then
  # No usable lockfile: fall back to the explicit "packageManager" field
  # (e.g. "pnpm@10.0.0") when it names one of the supported managers.
  field="$(jq -r '.packageManager // "" | split("@")[0]' "$root/package.json" 2>/dev/null || true)"
  case "$field" in
    pnpm | npm | yarn | bun) pm="$field" ;;
  esac
fi
formatter="$(detect_formatter "$root")"

# YAML parser for pnpm-workspace.yaml and the CI workflows: yq when available
# (and not disabled), else the line-oriented awk fallbacks below.
ci_parser="none"
if [ "${DISCOVER_YQ:-1}" != "0" ] && command -v yq >/dev/null 2>&1; then
  ci_parser="yq"
fi

lockfiles_json='[]'
for lock in pnpm-lock.yaml package-lock.json yarn.lock bun.lockb bun.lock; do
  if [ -f "$root/$lock" ]; then
    lockfiles_json="$(jq -c --arg l "$lock" '. + [$l]' <<<"$lockfiles_json")"
  fi
done

# ---------------------------------------------------------------------------
# Workspaces and apps
# ---------------------------------------------------------------------------

# workspace_globs — one glob per line, from pnpm-workspace.yaml (packages:)
# or package.json#workspaces (array or {packages: []}).
workspace_globs() {
  if [ -f "$root/pnpm-workspace.yaml" ]; then
    if [ "$ci_parser" = "yq" ]; then
      yq -r '.packages[]?' "$root/pnpm-workspace.yaml" 2>/dev/null || true
    else
      awk '
        /^packages:/ { inside = 1; next }
        inside && /^[^[:space:]-]/ { inside = 0 }
        inside && /^[[:space:]]*-[[:space:]]*/ {
          sub(/^[[:space:]]*-[[:space:]]*/, "")
          gsub(/^["'"'"']|["'"'"']$/, "")
          if ($0 != "") { print }
        }' "$root/pnpm-workspace.yaml"
    fi
  elif [ -f "$root/package.json" ]; then
    jq -r '.workspaces // [] | if type == "object" then (.packages // []) else . end | .[]' \
      "$root/package.json" 2>/dev/null || true
  fi
}

workspaces_json='[]'
while IFS= read -r glob; do
  if [ -n "$glob" ]; then
    workspaces_json="$(jq -c --arg g "$glob" '. + [$g]' <<<"$workspaces_json")"
  fi
done < <(workspace_globs)

# member_dirs — every directory matched by a workspace glob that holds a
# package.json, relative to the root, one per line. Without any declared
# workspace, the conventional apps/* layout is tried so a repo that keeps its
# apps there without a workspace file still gets a guess (a plain single
# package yields nothing). Negated globs (!…) are ignored.
member_dirs() {
  local glob dir
  local -a globs=()
  while IFS= read -r glob; do
    case "$glob" in
      "" | !*) continue ;;
    esac
    globs+=("${glob%/}")
  done < <(jq -r '.[]' <<<"$workspaces_json")
  if [ "${#globs[@]}" -eq 0 ]; then
    globs=("apps/*")
  fi
  for glob in "${globs[@]}"; do
    # shellcheck disable=SC2086  # the glob must expand
    for dir in "$root"/$glob; do
      if [ -f "$dir/package.json" ]; then
        printf '%s\n' "${dir#"$root/"}"
      fi
    done
  done
}

apps_json='{}'
scripts_json='{}'
if [ -f "$root/package.json" ]; then
  scripts_json="$(jq -c --arg k . '{($k): (.scripts // {})}' "$root/package.json" 2>/dev/null || printf '{}')"
fi
while IFS= read -r dir; do
  if [ -z "$dir" ] || [ "$dir" = "." ]; then
    continue
  fi
  name="$(basename "$dir")"
  apps_json="$(jq -c --arg n "$name" --arg p "$dir" '. + {($n): $p}' <<<"$apps_json")"
  scripts_json="$(jq -c --arg k "$dir" --slurpfile pkg "$root/$dir/package.json" \
    '. + {($k): ($pkg[0].scripts // {})}' <<<"$scripts_json" 2>/dev/null || printf '%s' "$scripts_json")"
done < <(member_dirs | sort -u)

# ---------------------------------------------------------------------------
# Branches
# ---------------------------------------------------------------------------

default_branch=""
branches_json='[]'
if in_git_repo "$root"; then
  if ref="$(git -C "$root" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    default_branch="${ref#origin/}"
  fi
  while IFS= read -r branch; do
    if [ -n "$branch" ]; then
      branches_json="$(jq -c --arg b "$branch" '. + [$b]' <<<"$branches_json")"
    fi
  done < <(git -C "$root" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)
  if [ -z "$default_branch" ]; then
    for candidate in main master; do
      if jq -e --arg b "$candidate" 'index($b) != null' <<<"$branches_json" >/dev/null; then
        default_branch="$candidate"
        break
      fi
    done
  fi
  if [ -z "$default_branch" ]; then
    default_branch="$(git -C "$root" branch --show-current 2>/dev/null || true)"
  fi
fi

# ---------------------------------------------------------------------------
# CI workflows
# ---------------------------------------------------------------------------

# workflow_jobs_yq <file> — JSON array of {name, run[]} via yq -o=json + jq.
workflow_jobs_yq() {
  yq -o=json '.' "$1" 2>/dev/null \
    | jq -c '(.jobs // {}) | to_entries | map({name: .key, run: [(.value.steps // [])[] | .run? // empty | tostring | sub("\n+$"; "")]})' \
    2>/dev/null || printf '[]'
}

# workflow_jobs_awk <file> — same shape from a line-oriented scan: a job is a
# key indented by exactly two spaces under "jobs:", a run: value is either
# inline or a "|" / ">" block whose lines are indented deeper than the key.
# Output: one "job<TAB>command" line per run: (newlines in blocks become \n).
workflow_jobs_awk() {
  awk '
    function indent(s) { match(s, /^[ ]*/); return RLENGTH }
    function flush() {
      if (in_block) { printf "%s\t%s\n", job, block; in_block = 0; block = "" }
    }
    /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
    in_jobs && /^[^[:space:]#]/ { flush(); in_jobs = 0 }
    !in_jobs { next }
    {
      ind = indent($0)
      if (in_block) {
        if ($0 ~ /^[[:space:]]*$/ || ind > block_indent) {
          line = $0
          sub(/^[ ]*/, "", line)
          block = (block == "" ? line : block "\\n" line)
          next
        }
        flush()
      }
      if (ind == 2 && $0 ~ /^  [A-Za-z0-9_-]+:[[:space:]]*$/) {
        job = $0
        sub(/^  /, "", job)
        sub(/:.*$/, "", job)
        next
      }
      if (job != "" && $0 ~ /^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]*/) {
        value = $0
        sub(/^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]*/, "", value)
        if (value ~ /^[|>]/) {
          in_block = 1
          block_indent = ind
          if ($0 ~ /^[[:space:]]*-[[:space:]]+run:/) { block_indent = ind + 2 }
          block = ""
        } else if (value != "") {
          gsub(/^["'"'"']|["'"'"']$/, "", value)
          printf "%s\t%s\n", job, value
        }
      }
    }
    END { flush() }' "$1" \
    | jq -Rs 'split("\n") | map(select(. != "") | split("\t") | {name: .[0], run: (.[1] | gsub("\\\\n"; "\n"))})
      | group_by(.name) | map({name: .[0].name, run: map(.run)})'
}

workflows_json='[]'
for wf in "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml; do
  if [ ! -f "$wf" ]; then
    continue
  fi
  if [ "$ci_parser" = "yq" ]; then
    jobs="$(workflow_jobs_yq "$wf")"
  else
    ci_parser="awk"
    jobs="$(workflow_jobs_awk "$wf")"
  fi
  workflows_json="$(jq -c --arg f "${wf#"$root/"}" --argjson j "$jobs" '. + [{file: $f, jobs: $j}]' <<<"$workflows_json")"
done

# ---------------------------------------------------------------------------
# Existing Claude config and .gitignore
# ---------------------------------------------------------------------------

claude_paths_json='[]'
claude_hooks_json='[]'
if [ -d "$root/.claude" ]; then
  while IFS= read -r path; do
    rel="${path#"$root/"}"
    claude_paths_json="$(jq -c --arg p "$rel" '. + [$p]' <<<"$claude_paths_json")"
    case "$rel" in
      .claude/hooks/*) claude_hooks_json="$(jq -c --arg p "$(basename "$rel")" '. + [$p]' <<<"$claude_hooks_json")" ;;
    esac
  done < <(find "$root/.claude" -type f -not -path '*/worktrees/*' 2>/dev/null | sort)
fi
has_claude_md=false
if [ -f "$root/CLAUDE.md" ]; then
  has_claude_md=true
fi
has_gitignore_claude=false
if [ -f "$root/.gitignore" ] && grep -qE '^!?\.claude(/|$)' "$root/.gitignore"; then
  has_gitignore_claude=true
fi

jq -n \
  --arg root "$root" \
  --arg pm "$pm" \
  --arg formatter "$formatter" \
  --argjson lockfiles "$lockfiles_json" \
  --argjson workspaces "$workspaces_json" \
  --argjson apps "$apps_json" \
  --argjson scripts "$scripts_json" \
  --arg defaultBranch "$default_branch" \
  --argjson branches "$branches_json" \
  --arg ciParser "$ci_parser" \
  --argjson ciWorkflows "$workflows_json" \
  --argjson claudeMd "$has_claude_md" \
  --argjson claudePaths "$claude_paths_json" \
  --argjson claudeHooks "$claude_hooks_json" \
  --argjson hasGitignoreClaude "$has_gitignore_claude" \
  '{
    root: $root,
    packageManager: (if $pm == "" then null else $pm end),
    formatter: $formatter,
    lockfiles: $lockfiles,
    workspaces: $workspaces,
    apps: $apps,
    packageScripts: $scripts,
    defaultBranch: (if $defaultBranch == "" then null else $defaultBranch end),
    branches: $branches,
    ciParser: $ciParser,
    ciWorkflows: $ciWorkflows,
    existingClaude: {claudeMd: $claudeMd, paths: $claudePaths, hooks: $claudeHooks},
    hasGitignoreClaude: $hasGitignoreClaude
  }'
