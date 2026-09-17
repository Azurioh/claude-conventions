# shellcheck shell=bash
# Shared library for the conventions hooks. Sourced by every hook script so
# they agree on what a shell "segment" is, how a command is spelled, where the
# project root is and how per-repo values are read from
# .claude/conventions.json (see contracts/conventions-json.md).

# Set by git_strip_opts: the path passed to "git -C <path>", empty otherwise.
# shellcheck disable=SC2034  # read by the sourcing hook, not by lib.sh
GIT_C_PATH=""
# Set by git_strip_opts to the same string it prints, so a caller that also needs
# GIT_C_PATH can read both without a command substitution (which would subshell).
# shellcheck disable=SC2034  # read by the sourcing hook, not by lib.sh
GIT_SEG=""
# Set by the sourcing hook from the event's .cwd; read by project_root when
# CLAUDE_PROJECT_DIR is unset and no explicit directory is passed.
HOOK_CWD=""

# ---------------------------------------------------------------------------
# Command normalisation
# ---------------------------------------------------------------------------

# split_segments <cmd> — prints one shell segment per line. Splits on && || ; |
# ( ) { } and newlines, then on the standalone keywords then / do / else.
# Anything inside a single- or double-quoted string is data, not syntax: it is
# copied through untouched, so a commit message or a PR body quoting a forbidden
# command never turns into a segment of its own. The segments keep the original
# text (quotes included) so the callers can still read flag values out of them.
split_segments() {
  local s="$1" n i ch out state boundary
  local sq="'" dq='"' bs=$'\\' nl=$'\n'
  n="${#s}"
  i=0
  out=""
  state=""
  boundary=1
  while [ "$i" -lt "$n" ]; do
    ch="${s:$i:1}"
    if [ -n "$state" ]; then
      # Inside a quoted string: only the matching close quote ends it, and a
      # backslash escapes the next character in a double-quoted one.
      if [ "$state" = "$dq" ] && [ "$ch" = "$bs" ]; then
        out="$out${s:$i:2}"
        i=$((i + 2))
        continue
      fi
      if [ "$ch" = "$state" ]; then
        state=""
      fi
      out="$out$ch"
      boundary=0
      i=$((i + 1))
      continue
    fi
    case "$ch" in
      "$sq" | "$dq")
        state="$ch"
        out="$out$ch"
        boundary=0
        i=$((i + 1))
        continue
        ;;
      "$bs")
        out="$out${s:$i:2}"
        boundary=0
        i=$((i + 2))
        continue
        ;;
      '&' | '|' | ';' | '(' | ')' | '{' | '}' | "$nl")
        out="$out$nl"
        boundary=1
        i=$((i + 1))
        continue
        ;;
    esac
    if [ "$boundary" -eq 1 ] && [[ "${s:$i}" =~ ^(then|do|else)([[:space:]]|$) ]]; then
      out="$out$nl"
      boundary=1
      i=$((i + ${#BASH_REMATCH[1]}))
      continue
    fi
    out="$out$ch"
    if [[ "$ch" =~ [[:space:]] ]]; then
      boundary=1
    else
      boundary=0
    fi
    i=$((i + 1))
  done
  printf '%s\n' "$out"
}

# normalize_segment <seg> — trims, then drops leading VAR=value assignments and
# the wrapper words command / env / exec / nohup / sudo.
normalize_segment() {
  local seg="$1" lead trail changed=1
  lead="${seg%%[![:space:]]*}"
  seg="${seg#"$lead"}"
  trail="${seg##*[![:space:]]}"
  seg="${seg%"$trail"}"
  while [ "$changed" -eq 1 ]; do
    changed=0
    if [[ "$seg" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*)$ ]]; then
      seg="${BASH_REMATCH[1]}"
      changed=1
    elif [[ "$seg" =~ ^(command|env|exec|nohup|sudo)[[:space:]]+(.*)$ ]]; then
      seg="${BASH_REMATCH[2]}"
      changed=1
    fi
  done
  printf '%s' "$seg"
}

# git_strip_opts <seg> — for a segment starting with "git", drops the leading
# -C <path> / -c <k=v> / --git-dir=… / --work-tree=… options and prints
# "git <subcommand> …". Exposes the -C path through GIT_C_PATH and the printed
# string through GIT_SEG.
git_strip_opts() {
  local seg="$1" rest lead changed=1
  GIT_C_PATH=""
  if ! [[ "$seg" =~ ^git([[:space:]]|$) ]]; then
    GIT_SEG="$seg"
    printf '%s' "$GIT_SEG"
    return 0
  fi
  rest="${seg#git}"
  lead="${rest%%[![:space:]]*}"
  rest="${rest#"$lead"}"
  while [ "$changed" -eq 1 ]; do
    changed=0
    if [[ "$rest" =~ ^-C[[:space:]]*([^[:space:]]+)[[:space:]]*(.*)$ ]]; then
      GIT_C_PATH="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
      changed=1
    elif [[ "$rest" =~ ^-c[[:space:]]*[^[:space:]]+[[:space:]]*(.*)$ ]]; then
      rest="${BASH_REMATCH[1]}"
      changed=1
    elif [[ "$rest" =~ ^(--git-dir|--work-tree)=[^[:space:]]*[[:space:]]*(.*)$ ]]; then
      rest="${BASH_REMATCH[2]}"
      changed=1
    elif [[ "$rest" =~ ^(--git-dir|--work-tree)[[:space:]]+[^[:space:]]+[[:space:]]*(.*)$ ]]; then
      rest="${BASH_REMATCH[2]}"
      changed=1
    fi
  done
  GIT_SEG="git $rest"
  printf '%s' "$GIT_SEG"
}

# strip_quotes <value> — removes one layer of surrounding single/double quotes.
strip_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

# flag_value_last <seg> <regex-alternation> — prints the value of the LAST
# occurrence of the flag (e.g. "--base|-B"), accepting "-Bx", "-B x" and "--base=x".
flag_value_last() {
  local seg="$1" flags="$2"
  if [[ "$seg" =~ .*($flags)([[:space:]]+|=)?([^[:space:]]+) ]]; then
    strip_quotes "${BASH_REMATCH[3]}"
  fi
}

# ---------------------------------------------------------------------------
# Project location
# ---------------------------------------------------------------------------

# in_git_repo [dir] — succeeds when <dir> (default: HOOK_CWD, then the current
# directory) is inside a git work tree.
in_git_repo() {
  local dir="${1:-${HOOK_CWD:-.}}"
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# project_root [cwd] — prints the project root: $CLAUDE_PROJECT_DIR when set,
# else <cwd> (default: HOOK_CWD), else the git toplevel of the current
# directory, else the current directory itself.
project_root() {
  local cwd="${1:-${HOOK_CWD:-}}" top
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  if [ -n "$cwd" ]; then
    printf '%s' "$cwd"
    return 0
  fi
  if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s' "$top"
    return 0
  fi
  pwd
}

# ---------------------------------------------------------------------------
# .claude/conventions.json
# ---------------------------------------------------------------------------

# conv_file [root] — prints the path of the conventions file for <root>
# (default: project_root).
conv_file() {
  local root="${1:-$(project_root)}"
  printf '%s/.claude/conventions.json' "$root"
}

# conv_warn <hook> <message> — prints a one-line warning in the hook format.
conv_warn() {
  printf 'conventions/%s: %s\n' "$1" "$2" >&2
}

# conv_jq_path <jq-path> — normalises "prSize.lines" / ".prSize.lines" to a
# jq filter starting with a dot.
conv_jq_path() {
  local path="$1"
  case "$path" in
    .*) printf '%s' "$path" ;;
    *) printf '.%s' "$path" ;;
  esac
}

# conv_get <jq-path> <default> [root] — prints the value at <jq-path> in the
# conventions file, one line per element for arrays, or <default> when the file,
# the key or jq is missing or the file is not valid JSON. An empty default
# prints nothing.
conv_get() {
  local path default="$2" file out
  path="$(conv_jq_path "$1")"
  file="$(conv_file "${3:-}")"
  if [ ! -f "$file" ] || ! command -v jq >/dev/null 2>&1; then
    if [ -n "$default" ]; then
      printf '%s\n' "$default"
    fi
    return 0
  fi
  if ! out="$(jq -r "(try ($path) catch null) as \$v
    | if \$v == null then empty
      elif (\$v | type) == \"array\" then \$v[]
      else \$v end" "$file" 2>/dev/null)"; then
    out=""
  fi
  if [ -z "$out" ]; then
    if [ -n "$default" ]; then
      printf '%s\n' "$default"
    fi
    return 0
  fi
  printf '%s\n' "$out"
}

# conv_require <jq-path> <hook> [root] — prints the value at <jq-path>; when the
# conventions file or the key is missing, warns on stderr in the hook format
# and returns 1 so the caller can skip its check (fail open).
conv_require() {
  local path="$1" hook="$2" file value
  file="$(conv_file "${3:-}")"
  if [ ! -f "$file" ]; then
    conv_warn "$hook" ".claude/conventions.json missing — skipped"
    return 1
  fi
  value="$(conv_get "$path" "" "${3:-}")"
  if [ -z "$value" ]; then
    conv_warn "$hook" ".claude/conventions.json has no ${path#.} — skipped"
    return 1
  fi
  printf '%s\n' "$value"
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

# detect_pm [root] — prints the package manager implied by the lockfile in
# <root> (pnpm / npm / yarn / bun). Prints nothing when no lockfile or more than
# one distinct package manager's lockfile is present.
detect_pm() {
  local root="${1:-$(project_root)}" found="" pm
  for pm in pnpm npm yarn bun; do
    case "$pm" in
      pnpm) [ -f "$root/pnpm-lock.yaml" ] || continue ;;
      npm) [ -f "$root/package-lock.json" ] || continue ;;
      yarn) [ -f "$root/yarn.lock" ] || continue ;;
      bun) [ -f "$root/bun.lockb" ] || [ -f "$root/bun.lock" ] || continue ;;
    esac
    if [ -n "$found" ]; then
      return 0
    fi
    found="$pm"
  done
  if [ -n "$found" ]; then
    printf '%s\n' "$found"
  fi
}

# detect_formatter [root] — prints biome (biome.json / biome.jsonc), prettier
# (.prettierrc*, prettier.config.*, or a "prettier" key in package.json) or none.
detect_formatter() {
  local root="${1:-$(project_root)}" candidate
  if [ -f "$root/biome.json" ] || [ -f "$root/biome.jsonc" ]; then
    printf 'biome\n'
    return 0
  fi
  for candidate in "$root"/.prettierrc "$root"/.prettierrc.* "$root"/prettier.config.*; do
    if [ -f "$candidate" ]; then
      printf 'prettier\n'
      return 0
    fi
  done
  if [ -f "$root/package.json" ] && command -v jq >/dev/null 2>&1 \
    && jq -e 'has("prettier")' "$root/package.json" >/dev/null 2>&1; then
    printf 'prettier\n'
    return 0
  fi
  printf 'none\n'
}

# production_branch [root] — prints the production branch: the productionBranch
# override from the conventions file, else the branch origin/HEAD points to,
# else main.
production_branch() {
  local root="${1:-$(project_root)}" value ref
  value="$(conv_get productionBranch "" "$root")"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return 0
  fi
  if ref="$(git -C "$root" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "${ref#origin/}"
    return 0
  fi
  printf 'main\n'
}
