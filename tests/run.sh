#!/usr/bin/env bash
# Hook test harness: copies each fixture under tests/fixtures/ into a temporary
# git repository, feeds hand-built stdin JSON events to the plugin hooks and
# asserts exit codes plus stderr content.
#
# Usage: tests/run.sh
# Exit: 0 when every assertion passed, 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$ROOT/plugins/conventions/hooks"
PORT_DIR="$ROOT/plugins/conventions/skills/port-claude-config"
FIXTURES_DIR="$ROOT/tests/fixtures"
TMP="$(mktemp -d)"
trap 'find "$TMP" -depth -delete' EXIT

export CLAUDE_PLUGIN_ROOT="$ROOT/plugins/conventions"
# Keep the user's git configuration (signing, hooks, default branch) out of
# the fixture repositories.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test
export GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test
export GIT_COMMITTER_EMAIL=test@example.com

PASSED=0
FAILED=0
# Path of the fixture repository created by the last mkfixture call.
FIXTURE=""
# Files holding the stdout / stderr of the last hook run by expect.
LAST_STDOUT="$TMP/last-stdout"
LAST_STDERR="$TMP/last-stderr"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# section <name> — prints a heading for the following assertions.
section() {
  printf '\n== %s\n' "$1"
}

# pass <label> / fail <label> <details…> — record one assertion.
pass() {
  PASSED=$((PASSED + 1))
  printf 'ok   %s\n' "$1"
}

fail() {
  local label="$1"
  shift
  FAILED=$((FAILED + 1))
  printf 'FAIL %s\n' "$label"
  local line
  for line in "$@"; do
    printf '     %s\n' "$line"
  done
}

# mkfixture <name> — copies tests/fixtures/<name> into a fresh temporary
# directory, initialises it as a git repository on main with one commit and,
# when the fixture ships .claude/conventions.json, creates its integration
# branch (default develop). A fixture without the file keeps main only. Sets
# FIXTURE and exports CLAUDE_PROJECT_DIR to the new path.
mkfixture() {
  local name="$1" dir integration
  dir="$TMP/$name-$RANDOM"
  mkdir -p "$dir"
  cp -R "$FIXTURES_DIR/$name/." "$dir"
  git init -q -b main "$dir"
  git -C "$dir" add -A
  git -C "$dir" commit -q --allow-empty -m "initial fixture state"
  if [ -f "$dir/.claude/conventions.json" ]; then
    integration="$(jq -r '.integrationBranch // "develop"' "$dir/.claude/conventions.json")"
    git -C "$dir" branch -q "$integration"
  fi
  FIXTURE="$dir"
  export CLAUDE_PROJECT_DIR="$dir"
}

# bash_event <command> [cwd] — prints a PreToolUse JSON event for the Bash tool.
bash_event() {
  jq -cn --arg cwd "${2:-$FIXTURE}" --arg cmd "$1" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}'
}

# edit_event <file-path> [cwd] — prints a PostToolUse JSON event for the Edit tool.
edit_event() {
  jq -cn --arg cwd "${2:-$FIXTURE}" --arg fp "$1" \
    '{hook_event_name:"PostToolUse",tool_name:"Edit",cwd:$cwd,tool_input:{file_path:$fp}}'
}

# session_event [cwd] — prints a SessionStart JSON event.
session_event() {
  jq -cn --arg cwd "${1:-$FIXTURE}" '{hook_event_name:"SessionStart",cwd:$cwd}'
}

# expect <exit> <hook> <stdin-json> [stderr-substring] — runs
# plugins/conventions/hooks/<hook>.sh with the JSON on stdin, asserts the exit
# code and, when given, that stderr contains the substring. stdout and stderr
# of the run are kept in LAST_STDOUT / LAST_STDERR.
expect() {
  local want="$1" hook="$2" json="$3" needle="${4:-}" got=0 label
  hook="${hook%.sh}"
  label="$hook exit=$want"
  if [ -n "$needle" ]; then
    label="$label stderr~'$needle'"
  fi
  printf '%s' "$json" | "$HOOKS_DIR/$hook.sh" >"$LAST_STDOUT" 2>"$LAST_STDERR" || got=$?
  if [ "$got" -ne "$want" ]; then
    fail "$label" "got exit=$got" "json=$json" "stderr=$(cat "$LAST_STDERR")"
    return 0
  fi
  if [ -n "$needle" ] && ! grep -qF -- "$needle" "$LAST_STDERR"; then
    fail "$label" "stderr lacks '$needle'" "json=$json" "stderr=$(cat "$LAST_STDERR")"
    return 0
  fi
  pass "$label"
}

# check <label> <command…> — records an assertion from the exit status of an
# arbitrary command (file content, stdout of the last hook, …).
check() {
  local label="$1"
  shift
  if "$@"; then
    pass "$label"
  else
    fail "$label" "command: $*"
  fi
}

# skip <label> <reason> — records nothing; prints why an assertion was not run.
skip() {
  printf 'SKIP %s (%s)\n' "$1" "$2"
}

# has_formatter <name> <root> — true when <name> is resolvable the way
# format.sh resolves it: <root>/node_modules/.bin/<name> or on PATH.
has_formatter() {
  [ -x "$2/node_modules/.bin/$1" ] || command -v "$1" >/dev/null 2>&1
}

# stdout_has <substring> / stdout_lacks <substring> — inspect the last hook's stdout.
stdout_has() {
  grep -qF -- "$1" "$LAST_STDOUT"
}

stdout_lacks() {
  ! grep -qF -- "$1" "$LAST_STDOUT"
}

# files_differ <a> <b> — true when the two files have different content.
files_differ() {
  ! cmp -s "$1" "$2"
}

# commit_files <branch> <count> <lines> <path-prefix> [suffix] — creates a
# branch from the current HEAD, writes <count> files of <lines> lines each
# under <path-prefix> and commits them. Used by the pr-size assertions.
commit_files() {
  local branch="$1" count="$2" lines="$3" prefix="$4" suffix="${5:-.ts}" i
  git -C "$FIXTURE" switch -q -c "$branch"
  for i in $(seq 1 "$count"); do
    mkdir -p "$(dirname "$FIXTURE/$prefix$i$suffix")"
    seq 1 "$lines" | sed 's/^/line /' >"$FIXTURE/$prefix$i$suffix"
  done
  git -C "$FIXTURE" add -A
  git -C "$FIXTURE" commit -q -m "fixture: $branch"
}

# ---------------------------------------------------------------------------
# Assertions (one section per fixture/hook)
# ---------------------------------------------------------------------------

# --- guard-git (pnpm-biome) --------------------------------------------------
mkfixture pnpm-biome
section "guard-git (pnpm-biome, on main)"
expect 2 guard-git "$(bash_event 'git push --force origin develop')" 'conventions/guard-git:'
expect 2 guard-git "$(bash_event 'git push -f')" 'conventions/guard-git:'
expect 2 guard-git "$(bash_event 'git push --force-with-lease')" 'conventions/guard-git:'
expect 2 guard-git "$(bash_event 'git stash')" 'conventions/guard-git:'
expect 2 guard-git "$(bash_event 'git stash pop')" 'conventions/guard-git:'
expect 0 guard-git "$(bash_event 'git stash push -u -m x')"
expect 2 guard-git "$(bash_event 'git commit -m x')" 'conventions/guard-git:'
expect 2 guard-git "$(bash_event 'gh pr create --base main --title t')" 'conventions/guard-git:'
expect 0 guard-git "$(bash_event 'gh pr create --base develop --title t')"
expect 0 guard-git "$(bash_event 'gh pr create --base main --head develop --title "release: x"')"
expect 0 guard-git "$(bash_event 'ls')"
check "guard-git: ls is silent" test ! -s "$LAST_STDERR"

git -C "$FIXTURE" switch -q -c feat/x
section "guard-git (pnpm-biome, on feat/x)"
expect 0 guard-git "$(bash_event 'git commit -m x')"
expect 2 guard-git "$(bash_event 'git push --force origin develop')" 'conventions/guard-git:'
expect 2 guard-git "$(bash_event 'git push origin HEAD:refs/heads/main')" 'conventions/guard-git:'
expect 0 guard-git "$(bash_event 'git push --force-with-lease origin feat/x')"
expect 2 guard-git "$(bash_event 'pnpm test && git stash')" 'conventions/guard-git:'
expect 0 guard-git "$(bash_event 'git stash apply abc123')"

mkdir -p "$TMP/nogit"
expect 0 guard-git "$(bash_event 'git push --force origin main' "$TMP/nogit")"
check "guard-git: outside git is silent" test ! -s "$LAST_STDERR"

# --- deps-exact (pnpm-biome) -------------------------------------------------
mkfixture pnpm-biome
section "deps-exact (pnpm-biome)"
expect 2 deps-exact "$(bash_event 'pnpm add lodash')" '-E'
expect 0 deps-exact "$(bash_event 'pnpm add -E lodash')"
expect 0 deps-exact "$(bash_event 'pnpm add --save-exact lodash')"
expect 2 deps-exact "$(bash_event 'pnpm add -D lodash')" 'conventions/deps-exact:'
expect 0 deps-exact "$(bash_event 'pnpm install')"
expect 0 deps-exact "$(bash_event 'pnpm remove lodash')"
expect 0 deps-exact "$(bash_event 'pnpm add lodash@4.17.21')"
expect 0 deps-exact "$(bash_event 'pnpm add lodash' "$TMP/nogit")"
check "deps-exact: outside git is silent" test ! -s "$LAST_STDERR"

# --- pr-size (pnpm-biome) ----------------------------------------------------
mkfixture pnpm-biome
section "pr-size (pnpm-biome)"
commit_files feat/many-files 20 1 src/many/f
expect 2 pr-size "$(bash_event 'gh pr create --base develop --title t')" 'conventions/pr-size:'

git -C "$FIXTURE" switch -q develop
commit_files feat/lines-401 1 401 src/big
expect 2 pr-size "$(bash_event 'gh pr create --base develop --title t')" 'conventions/pr-size:'
expect 0 pr-size "$(bash_event 'gh pr create --base develop --title t --label large-pr')"
expect 0 pr-size "$(bash_event 'gh pr create --base develop --title t -l docs,large-pr')"

git -C "$FIXTURE" switch -q develop
commit_files feat/lines-400 1 400 src/ok
expect 0 pr-size "$(bash_event 'gh pr create --base develop --title t')"

git -C "$FIXTURE" switch -q develop
git -C "$FIXTURE" switch -q -c feat/excluded
seq 1 300 | sed 's/^/lock /' >>"$FIXTURE/pnpm-lock.yaml"
mkdir -p "$FIXTURE/apps/api/migrations"
seq 1 300 | sed 's/^/-- /' >"$FIXTURE/apps/api/migrations/x.sql"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" commit -q -m "fixture: excluded paths"
expect 0 pr-size "$(bash_event 'gh pr create --base develop --title t')"

git -C "$FIXTURE" switch -q develop
seq 1 500 | sed 's/^/release /' >"$FIXTURE/src/release.ts"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" commit -q -m "fixture: oversize integration branch"
expect 0 pr-size "$(bash_event 'gh pr create --base main --head develop --title "release: x"')"
expect 2 pr-size "$(bash_event 'gh pr create --base main --title t')" 'conventions/pr-size:'

# --- format (pnpm-biome) -----------------------------------------------------
mkfixture pnpm-biome
section "format (pnpm-biome)"
cp "$FIXTURE/src/index.ts" "$TMP/index.ts.before"
printf '#   fixture\n\n\n\nunformatted   markdown\n' >"$FIXTURE/README.md"
cp "$FIXTURE/README.md" "$TMP/README.md.before"
expect 0 format "$(edit_event "$FIXTURE/src/index.ts")"
if has_formatter biome "$FIXTURE"; then
  check "format: src/index.ts reformatted" test ! -s "$LAST_STDERR"
  check "format: src/index.ts content changed" files_differ "$TMP/index.ts.before" "$FIXTURE/src/index.ts"
else
  skip "format: src/index.ts content changed" "biome not resolvable in the fixture"
fi
expect 0 format "$(edit_event "$FIXTURE/README.md")"
check "format: README.md untouched" cmp -s "$TMP/README.md.before" "$FIXTURE/README.md"
expect 0 format "$(edit_event "$FIXTURE/src/missing.ts")"
expect 0 format '{"hook_event_name":"PostToolUse","tool_name":"Edit","cwd":"'"$FIXTURE"'","tool_input":{}}'

# --- branch-info (pnpm-biome) ------------------------------------------------
mkfixture pnpm-biome
section "branch-info (pnpm-biome)"
expect 0 branch-info "$(session_event)"
check "branch-info: prints main" stdout_has "main"
check "branch-info: warns on main" stdout_has "WARNING"
git -C "$FIXTURE" switch -q -c feat/x
expect 0 branch-info "$(session_event)"
check "branch-info: prints feat/x" stdout_has "feat/x"
check "branch-info: no warning on feat/x" stdout_lacks "WARNING"
expect 0 branch-info "$(session_event "$TMP/nogit")"
check "branch-info: empty stdout outside git" test ! -s "$LAST_STDOUT"

# --- guard-git (npm-prettier) ------------------------------------------------
# The fixture's conventions.json only sets integrationBranch and the repository
# has no remote: the production branch comes from the origin/HEAD fallback (main).
mkfixture npm-prettier
section "guard-git (npm-prettier, production = origin/HEAD fallback main)"
expect 2 guard-git "$(bash_event 'git commit -m x')" "no commits on 'main'"
expect 2 guard-git "$(bash_event 'git push --force origin main')" "force push to 'main'"
expect 2 guard-git "$(bash_event 'git push origin develop')" "direct push to 'develop'"
expect 2 guard-git "$(bash_event 'gh pr create --base main --title t')" 'conventions/guard-git:'
expect 0 guard-git "$(bash_event 'gh pr create --base main --head develop --title "release: x"')"
git -C "$FIXTURE" switch -q -c feat/x
expect 0 guard-git "$(bash_event 'git commit -m x')"
expect 0 guard-git "$(bash_event 'gh pr create --base develop --title t')"
check "guard-git: feat/x is silent" test ! -s "$LAST_STDERR"

# --- deps-exact (npm-prettier) -----------------------------------------------
mkfixture npm-prettier
section "deps-exact (npm-prettier)"
expect 2 deps-exact "$(bash_event 'npm install lodash')" '--save-exact'
expect 0 deps-exact "$(bash_event 'npm install --save-exact lodash')"
expect 0 deps-exact "$(bash_event 'npm install -E lodash')"
expect 2 deps-exact "$(bash_event 'npm i -D lodash')" 'npm i --save-exact -D lodash'
expect 0 deps-exact "$(bash_event 'npm install')"
expect 0 deps-exact "$(bash_event 'npm install lodash@4.17.21')"
expect 0 deps-exact "$(bash_event 'pnpm add lodash')"
check "deps-exact: another manager's segment is silent" test ! -s "$LAST_STDERR"

# --- pr-size (npm-prettier) --------------------------------------------------
mkfixture npm-prettier
section "pr-size (npm-prettier, default cap 400 lines / 15 files)"
commit_files feat/files-16 16 1 src/many/f
expect 2 pr-size "$(bash_event 'gh pr create --base develop --title t')" 'cap 400 lines, 15 files'
git -C "$FIXTURE" switch -q develop
commit_files feat/files-15 15 1 src/some/f
expect 0 pr-size "$(bash_event 'gh pr create --base develop --title t')"
git -C "$FIXTURE" switch -q develop
commit_files feat/lines-401 1 401 src/big
expect 2 pr-size "$(bash_event 'gh pr create --base develop --title t')" 'cap 400 lines, 15 files'
expect 0 pr-size "$(bash_event 'gh pr create --base develop --title t --label large-pr')"
git -C "$FIXTURE" switch -q develop
commit_files feat/lines-400 1 400 src/ok
expect 0 pr-size "$(bash_event 'gh pr create --base develop --title t')"
git -C "$FIXTURE" switch -q develop
git -C "$FIXTURE" switch -q -c feat/lockfile
seq 1 500 | sed 's/^/lock /' >>"$FIXTURE/package-lock.json"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" commit -q -m "fixture: package-lock.json excluded by default"
expect 0 pr-size "$(bash_event 'gh pr create --base develop --title t')"

# --- format (npm-prettier) ---------------------------------------------------
mkfixture npm-prettier
section "format (npm-prettier)"
cp "$FIXTURE/src/index.ts" "$TMP/index-npm.ts.before"
expect 0 format "$(edit_event "$FIXTURE/src/index.ts")"
if has_formatter prettier "$FIXTURE"; then
  check "format: prettier ran silently" test ! -s "$LAST_STDERR"
  check "format: src/index.ts content changed" files_differ "$TMP/index-npm.ts.before" "$FIXTURE/src/index.ts"
  check "format: .prettierrc applied (single quotes)" grep -qF "'hello, '" "$FIXTURE/src/index.ts"
else
  skip "format: src/index.ts content changed" "prettier not resolvable in the fixture"
fi

# --- branch-info (npm-prettier) ----------------------------------------------
mkfixture npm-prettier
section "branch-info (npm-prettier)"
expect 0 branch-info "$(session_event)"
check "branch-info: main is production (origin/HEAD fallback)" stdout_has "WARNING: on main — branch off develop first"
git -C "$FIXTURE" switch -q develop
expect 0 branch-info "$(session_event)"
check "branch-info: warns on develop" stdout_has "WARNING: on develop"

# --- guard-git (no-conventions) ----------------------------------------------
# No .claude/ at all: the checks that need the integration branch warn once and
# pass; the stash rule needs no value and still applies.
mkfixture no-conventions
section "guard-git (no-conventions)"
expect 0 guard-git "$(bash_event 'git push --force origin main')" 'conventions/guard-git: .claude/conventions.json missing — skipped'
expect 0 guard-git "$(bash_event 'gh pr create --base main --title t')" 'conventions/guard-git: .claude/conventions.json missing — skipped'
expect 0 guard-git "$(bash_event 'git commit -m x')" '.claude/conventions.json missing — skipped'
check "guard-git: the warning is a single line" test "$(wc -l <"$LAST_STDERR")" -eq 1
expect 2 guard-git "$(bash_event 'git stash')" 'conventions/guard-git:'
expect 0 guard-git "$(bash_event 'ls')"
check "guard-git: ls is silent without conventions.json" test ! -s "$LAST_STDERR"

# --- deps-exact (no-conventions) ---------------------------------------------
mkfixture no-conventions
section "deps-exact (no-conventions)"
expect 2 deps-exact "$(bash_event 'pnpm add lodash')" '-E'
check "deps-exact: lockfile detection needs no conventions.json" test "$(grep -c 'conventions.json' "$LAST_STDERR")" = 0
expect 0 deps-exact "$(bash_event 'pnpm add -E lodash')"
check "deps-exact: exact pin is silent" test ! -s "$LAST_STDERR"

# --- pr-size (no-conventions) ------------------------------------------------
mkfixture no-conventions
section "pr-size (no-conventions, default cap)"
commit_files feat/files-16 16 1 src/many/f
expect 2 pr-size "$(bash_event 'gh pr create --base main --title t')" 'cap 400 lines, 15 files'
check "pr-size: default cap needs no conventions.json" test "$(grep -c 'conventions.json' "$LAST_STDERR")" = 0

# --- format (no-conventions) -------------------------------------------------
mkfixture no-conventions
section "format (no-conventions, no formatter config)"
printf 'const   a = 1\n' >"$FIXTURE/src.ts"
expect 0 format "$(edit_event "$FIXTURE/src.ts")"
check "format: silent without a formatter" test ! -s "$LAST_STDERR"
check "format: file untouched" test "$(cat "$FIXTURE/src.ts")" = 'const   a = 1'

# --- branch-info (no-conventions) --------------------------------------------
mkfixture no-conventions
section "branch-info (no-conventions)"
expect 0 branch-info "$(session_event)"
check "branch-info: prints main" stdout_has "git branch: main"
check "branch-info: hints at the port skill" stdout_has "no .claude/conventions.json — run /conventions:port-claude-config"
check "branch-info: stderr is empty" test ! -s "$LAST_STDERR"

# --- deps-exact (no-conventions, two lockfiles) ------------------------------
section "deps-exact (no-conventions, pnpm-lock.yaml + package-lock.json)"
printf '{\n  "lockfileVersion": 3\n}\n' >"$FIXTURE/package-lock.json"
expect 0 deps-exact "$(bash_event 'pnpm add lodash')" 'ambiguous'
check "deps-exact: ambiguity warning names packageManager" grep -qF 'set packageManager in .claude/conventions.json' "$LAST_STDERR"
expect 0 deps-exact "$(bash_event 'npm install lodash')" 'ambiguous'

# --- port/discover (all fixtures) -------------------------------------------
# discover_json <label> <jq-filter> [DISCOVER_YQ] — runs discover.sh on the
# current fixture and records whether the jq filter holds on its output.
# The output is kept in LAST_STDOUT.
discover_json() {
  local label="$1" filter="$2" yq="${3:-1}" got=0
  DISCOVER_YQ="$yq" "$PORT_DIR/scripts/discover.sh" "$FIXTURE" >"$LAST_STDOUT" 2>"$LAST_STDERR" || got=$?
  if [ "$got" -ne 0 ]; then
    fail "$label" "discover.sh exit=$got" "stderr=$(cat "$LAST_STDERR")"
    return 0
  fi
  if jq -e "$filter" "$LAST_STDOUT" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label" "filter: $filter" "json=$(jq -c . "$LAST_STDOUT" 2>/dev/null || cat "$LAST_STDOUT")"
  fi
}

# fixture_present <name> — true when tests/fixtures/<name> exists and holds
# at least one file (a fixture directory that a later batch fills is skipped).
fixture_present() {
  [ -d "$FIXTURES_DIR/$1" ] && [ -n "$(find "$FIXTURES_DIR/$1" -type f -print -quit)" ]
}

# write_workflow — drops a two-job CI workflow (inline and block run: values)
# into the current fixture.
write_workflow() {
  mkdir -p "$FIXTURE/.github/workflows"
  cat >"$FIXTURE/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [push]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Lint
        run: npm run lint
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          npm ci
          npm test
YAML
}

section "port/discover (pnpm-biome)"
mkfixture pnpm-biome
discover_json "discover: packageManager pnpm" '.packageManager == "pnpm"'
discover_json "discover: formatter biome" '.formatter == "biome"'
discover_json "discover: apps guess {api: apps/api}" '.apps == {api: "apps/api"}'
discover_json "discover: lockfiles" '.lockfiles == ["pnpm-lock.yaml"]'
discover_json "discover: defaultBranch main" '.defaultBranch == "main"'
discover_json "discover: branches hold main and develop" '(.branches | index("main")) != null and (.branches | index("develop")) != null'
discover_json "discover: existing conventions.json listed" '.existingClaude.paths == [".claude/conventions.json"] and .existingClaude.claudeMd == false'
discover_json "discover: no .claude in .gitignore" '.hasGitignoreClaude == false'
discover_json "discover: root scripts read" '.packageScripts["."].lint == "echo lint ok" and .packageScripts["apps/api"].test == "echo api test ok"'
discover_json "discover: no workflow → empty list" '.ciWorkflows == []'
write_workflow
printf '.claude/*\n!.claude/rules/\n' >"$FIXTURE/.gitignore"
WORKFLOW_FILTER='.ciWorkflows == [{file: ".github/workflows/ci.yml", jobs: [{name: "lint", run: ["npm run lint"]}, {name: "test", run: ["npm ci\nnpm test"]}]}]'
if command -v yq >/dev/null 2>&1; then
  discover_json "discover: workflow jobs and run lines (yq)" "$WORKFLOW_FILTER and .ciParser == \"yq\""
else
  skip "discover: workflow jobs and run lines (yq)" "yq not installed"
fi
discover_json "discover: workflow jobs and run lines (awk fallback)" "$WORKFLOW_FILTER and .ciParser == \"awk\"" 0
discover_json "discover: .claude in .gitignore detected" '.hasGitignoreClaude == true'
mkdir -p "$FIXTURE/.claude/hooks"
printf '#!/usr/bin/env bash\nexit 0\n' >"$FIXTURE/.claude/hooks/guard-git.sh"
discover_json "discover: existing hooks listed" '.existingClaude.hooks == ["guard-git.sh"]'

section "port/discover (npm-prettier)"
if fixture_present npm-prettier; then
  mkfixture npm-prettier
  discover_json "discover: packageManager npm" '.packageManager == "npm"'
  discover_json "discover: formatter prettier" '.formatter == "prettier"'
  discover_json "discover: apps is an object" '.apps | type == "object"'
else
  skip "discover: npm-prettier" "fixture tests/fixtures/npm-prettier missing or empty"
fi

section "port/discover (no-conventions)"
if fixture_present no-conventions; then
  mkfixture no-conventions
  discover_json "discover: packageManager from the lockfile" '.packageManager != null'
  discover_json "discover: formatter none" '.formatter == "none"'
  discover_json "discover: no apps" '.apps == {}'
  discover_json "discover: no existing Claude config" '.existingClaude.paths == []'
else
  skip "discover: no-conventions" "fixture tests/fixtures/no-conventions missing or empty"
fi

section "port/discover (outside git)"
mkdir -p "$TMP/nogit-discover"
printf '{"name":"x"}\n' >"$TMP/nogit-discover/package.json"
FIXTURE="$TMP/nogit-discover"
discover_json "discover: outside git → null branch, empty lists" '.defaultBranch == null and .branches == [] and .packageManager == null and .apps == {}'

# --- port/render -------------------------------------------------------------
# render_ok <label> <template> <conventions> [extra args…] — renders and
# asserts exit 0 with no {{PLACEHOLDER}} left; output kept in LAST_STDOUT.
render_ok() {
  local label="$1" template="$2" conventions="$3" got=0
  shift 3
  "$PORT_DIR/scripts/render.sh" "$template" "$conventions" "$@" >"$LAST_STDOUT" 2>"$LAST_STDERR" || got=$?
  if [ "$got" -ne 0 ]; then
    fail "$label" "render.sh exit=$got" "stderr=$(cat "$LAST_STDERR")"
    return 0
  fi
  if grep -qE '\{\{[A-Z_]+\}\}' "$LAST_STDOUT"; then
    fail "$label" "placeholder left: $(grep -oE '\{\{[A-Z_]+\}\}' "$LAST_STDOUT" | sort -u | tr '\n' ' ')"
    return 0
  fi
  pass "$label"
}

# render_fails <label> <placeholder> <template> <conventions> [extra args…] —
# asserts exit 1 and that stderr names the placeholder.
render_fails() {
  local label="$1" placeholder="$2" template="$3" conventions="$4" got=0
  shift 4
  "$PORT_DIR/scripts/render.sh" "$template" "$conventions" "$@" >"$LAST_STDOUT" 2>"$LAST_STDERR" || got=$?
  if [ "$got" -ne 1 ]; then
    fail "$label" "expected exit=1, got exit=$got" "stderr=$(cat "$LAST_STDERR")"
    return 0
  fi
  if ! grep -qF -- "unresolved placeholder $placeholder" "$LAST_STDERR"; then
    fail "$label" "stderr lacks 'unresolved placeholder $placeholder'" "stderr=$(cat "$LAST_STDERR")"
    return 0
  fi
  pass "$label"
}

section "port/render"
mkfixture pnpm-biome
TPL="$PORT_DIR/templates"
FULL_CONV="$TMP/conventions-full.json"
jq '. + {packageManager: "pnpm", formatter: "biome"}' "$FIXTURE/.claude/conventions.json" >"$FULL_CONV"
printf '| App | Path | Stack | Verify |\n|---|---|---|---|\n| api | %sapps/api%s | node | %s.claude/rules/api/commands.md%s |\n' '`' '`' '`' '`' >"$TMP/app-table.md"
printf '["Bash(pnpm lint*)", "Bash(git status*)"]\n' >"$TMP/permissions.json"

render_fails "render: fixture conventions lack packageManager → exit 1" '{{PKG_MANAGER}}' "$TPL/rules/workflow.md" "$FIXTURE/.claude/conventions.json"
render_fails "render: CLAUDE.md without --app-table → exit 1" '{{APP_TABLE}}' "$TPL/CLAUDE.md" "$FULL_CONV"
render_fails "render: settings.json without --permissions → exit 1" '{{PERMISSIONS}}' "$TPL/settings.json" "$FULL_CONV"
printf 'x {{NOT_A_PLACEHOLDER}} y\n' >"$TMP/bogus.md"
render_fails "render: unknown placeholder → exit 1" '{{NOT_A_PLACEHOLDER}}' "$TMP/bogus.md" "$FULL_CONV"

render_ok "render: CLAUDE.md" "$TPL/CLAUDE.md" "$FULL_CONV" --app-table "$TMP/app-table.md"
check "render: CLAUDE.md carries the app table" stdout_has "| api | \`apps/api\` |"
check "render: CLAUDE.md names the integration branch" stdout_has "Every PR targets \`develop\`"
check "render: CLAUDE.md empty deploy note" stdout_has "is **production**. \`develop\`"
check "render: CLAUDE.md ≤ 40 lines" test "$(wc -l <"$LAST_STDOUT")" -le 40
for tpl in workflow architecture knowledge pitfalls commands; do
  render_ok "render: rules/$tpl.md" "$TPL/rules/$tpl.md" "$FULL_CONV"
done
render_ok "render: rules/workflow.md exact flag" "$TPL/rules/workflow.md" "$FULL_CONV"
check "render: workflow.md uses pnpm add -E" stdout_has 'pnpm add -E <pkg>'
check "render: workflow.md size cap defaults" stdout_has '≤ 400 changed lines'
render_ok "render: rules/architecture.md" "$TPL/rules/architecture.md" "$FULL_CONV"
check "render: architecture.md has the Test layout table" stdout_has '| layer | source glob | test dir | test kind |'
check "render: architecture.md has sentinels" stdout_has '<!-- conventions:begin architecture.ports -->'
render_ok "render: rules/knowledge.md" "$TPL/rules/knowledge.md" "$FULL_CONV"
check "render: knowledge.md default ADR dir" stdout_has 'docs/adr/NNNN-<slug>.md'
render_ok "render: gitignore" "$TPL/gitignore" "$FULL_CONV"
check "render: gitignore negates rules/" stdout_has '!.claude/rules/'
render_ok "render: settings.json" "$TPL/settings.json" "$FULL_CONV" --permissions "$TMP/permissions.json"
check "render: settings.json is JSON with empty enabledPlugins and force-push denied" \
  jq -e '.enabledPlugins == {} and (.permissions.deny | index("Bash(git push --force*)")) != null and (.permissions.allow | index("Bash(pnpm lint*)")) != null and (has("hooks") | not)' "$LAST_STDOUT" >/dev/null
render_ok "render: conventions.json" "$TPL/conventions.json" "$FULL_CONV"
# shellcheck disable=SC2016  # "$schema" is a jq key, not a shell variable
check "render: conventions.json is JSON with the schema and defaults" \
  jq -e '(.["$schema"] | endswith("schema/conventions.schema.json")) and .integrationBranch == "develop" and .prSize.lines == 400 and .prSize.label == "large-pr" and .adrDir == "docs/adr"' "$LAST_STDOUT" >/dev/null

NPM_CONV="$TMP/conventions-npm.json"
jq -n '{integrationBranch: "develop", packageManager: "npm", deployNote: "deployed on merge", prSize: {lines: 300, files: 10, label: "big"}, adrDir: "doc/decisions"}' >"$NPM_CONV"
render_ok "render: npm + deploy note + overrides" "$TPL/rules/workflow.md" "$NPM_CONV"
check "render: npm exact flag" stdout_has 'npm add --save-exact <pkg>'
check "render: production defaults to main with the deploy note" stdout_has "\`main\` = production (deployed on merge)"
check "render: size cap overrides" stdout_has '≤ 300 changed lines'
check "render: label override" stdout_has '--label big'
render_ok "render: knowledge.md adrDir override" "$TPL/rules/knowledge.md" "$NPM_CONV"
check "render: adrDir override" stdout_has 'doc/decisions/NNNN-<slug>.md'
check "render: missing conventions file → exit 1" test "$("$PORT_DIR/scripts/render.sh" "$TPL/gitignore" "$TMP/does-not-exist.json" >/dev/null 2>&1; echo $?)" = 1

# --- port/refresh ------------------------------------------------------------
# port_fixture — renders the sentinel-bearing templates into the current
# fixture the way the port skill does (CLAUDE.md with an app table,
# rules/{workflow,architecture,knowledge,pitfalls}.md, one commands.md for the
# api app) from a conventions.json holding every value the templates need.
port_fixture() {
  local f
  jq '. + {packageManager: "pnpm", formatter: "biome", deployNote: "deployed on merge"}' \
    "$FIXTURE/.claude/conventions.json" >"$TMP/conventions-ported.json"
  cp "$TMP/conventions-ported.json" "$FIXTURE/.claude/conventions.json"
  mkdir -p "$FIXTURE/.claude/rules/api"
  "$PORT_DIR/scripts/render.sh" "$TPL/CLAUDE.md" "$FIXTURE/.claude/conventions.json" --app-table "$TMP/app-table.md" >"$FIXTURE/CLAUDE.md"
  for f in workflow architecture knowledge pitfalls; do
    "$PORT_DIR/scripts/render.sh" "$TPL/rules/$f.md" "$FIXTURE/.claude/conventions.json" >"$FIXTURE/.claude/rules/$f.md"
  done
  printf -- '---\npaths:\n  - "apps/api/**"\n---\n\n# api — commands\n\n    pnpm -C apps/api lint && pnpm -C apps/api test\n' >"$FIXTURE/.claude/rules/api/commands.md"
}

# rewrite <file> <command…> — replaces <file> with the stdout of the command
# run on it (portable in-place edit: no sed -i).
rewrite() {
  local file="$1"
  shift
  "$@" "$file" >"$TMP/rewrite.tmp"
  cp "$TMP/rewrite.tmp" "$file"
}

# drop_section <id> <file> — prints <file> without the sentinel section <id>.
drop_section() {
  awk -v id="$1" '
    $1 == "<!--" && $2 == "conventions:begin" && $3 == id { drop = 1 }
    !drop { print }
    $1 == "<!--" && $2 == "conventions:end" && $3 == id { drop = 0 }
  ' "$2"
}

# refresh_run <label> <expected-exit> [templates-dir] — runs refresh.sh on the
# current fixture (templates from <templates-dir> when given) and asserts the
# exit code; stdout (the changed-file list) is kept in LAST_STDOUT.
refresh_run() {
  local label="$1" want="$2" templates="${3:-}" got=0
  if [ -n "$templates" ]; then
    CONVENTIONS_TEMPLATES_DIR="$templates" "$PORT_DIR/scripts/refresh.sh" "$FIXTURE" >"$LAST_STDOUT" 2>"$LAST_STDERR" || got=$?
  else
    "$PORT_DIR/scripts/refresh.sh" "$FIXTURE" >"$LAST_STDOUT" 2>"$LAST_STDERR" || got=$?
  fi
  if [ "$got" -ne "$want" ]; then
    fail "$label" "refresh.sh exit=$got" "stdout=$(cat "$LAST_STDOUT")" "stderr=$(cat "$LAST_STDERR")"
    return 0
  fi
  pass "$label"
}

# outside_sentinels <file> — prints the lines of <file> that sit outside every
# sentinel section (the sentinel lines themselves included), so two files can
# be compared on their project-owned text only.
outside_sentinels() {
  awk '
    $1 == "<!--" && $2 == "conventions:begin" && $4 == "-->" && NF == 4 { print; inside = 1; next }
    $1 == "<!--" && $2 == "conventions:end" && $4 == "-->" && NF == 4 { print; inside = 0; next }
    !inside { print }
  ' "$1"
}

# same_outside <a> <b> — true when both files agree outside the sentinels.
same_outside() {
  outside_sentinels "$1" >"$TMP/outside-a"
  outside_sentinels "$2" >"$TMP/outside-b"
  cmp -s "$TMP/outside-a" "$TMP/outside-b"
}

# starts_with <prefix-file> <file> — true when <file> begins with the whole
# content of <prefix-file>.
starts_with() {
  head -n "$(wc -l <"$1")" "$2" >"$TMP/starts-with.tmp"
  cmp -s "$1" "$TMP/starts-with.tmp"
}

section "port/refresh"
mkfixture pnpm-biome
port_fixture
SNAP="$TMP/refresh-before"
mkdir -p "$SNAP"
# Project-owned edits that must survive: text outside the sentinels, a
# pitfalls entry, a Test layout row, a per-app sheet.
printf '\n## Local notes\n\nHand-written paragraph kept by the project.\n' >>"$FIXTURE/CLAUDE.md"
printf -- '- 2026-09-17 — flaky clock test → real Date.now() → freeze the clock in the twin\n' >>"$FIXTURE/.claude/rules/pitfalls.md"
rewrite "$FIXTURE/.claude/rules/architecture.md" sed '/^| other |/s#tests#tests/unit#'
check "refresh: fixture Test layout row edited" grep -qF 'tests/unit' "$FIXTURE/.claude/rules/architecture.md"
cp -R "$FIXTURE/.claude" "$SNAP/.claude"
cp "$FIXTURE/CLAUDE.md" "$SNAP/CLAUDE.md"

refresh_run "refresh: unchanged templates → exit 0" 0
check "refresh: unchanged templates → no changed file" test ! -s "$LAST_STDOUT"
check "refresh: unchanged templates → CLAUDE.md byte-identical" cmp -s "$SNAP/CLAUDE.md" "$FIXTURE/CLAUDE.md"
check "refresh: unchanged templates → workflow.md byte-identical" cmp -s "$SNAP/.claude/rules/workflow.md" "$FIXTURE/.claude/rules/workflow.md"

# A modified template: one line changed inside workflow.commits; one section
# removed from the fixture's knowledge.md to exercise the append path.
EDITED_TPL="$TMP/templates-edited"
cp -R "$TPL" "$EDITED_TPL"
rewrite "$EDITED_TPL/rules/workflow.md" sed "s#^- \*\*Never commit without the user's OK.\*\*\$#- **Never commit without the user's explicit OK (refreshed line).**#"
check "refresh: edited template carries the new line" grep -qF 'refreshed line' "$EDITED_TPL/rules/workflow.md"
rewrite "$FIXTURE/.claude/rules/knowledge.md" drop_section knowledge.pitfalls
cp "$FIXTURE/.claude/rules/knowledge.md" "$SNAP/.claude/rules/knowledge.md"

refresh_run "refresh: edited template → exit 0" 0 "$EDITED_TPL"
check "refresh: changed-file list is exactly knowledge.md and workflow.md" \
  test "$(sort "$LAST_STDOUT" | tr '\n' ' ')" = ".claude/rules/knowledge.md .claude/rules/workflow.md "
check "refresh: changed line landed inside workflow.commits" grep -qF 'explicit OK (refreshed line)' "$FIXTURE/.claude/rules/workflow.md"
check "refresh: old line gone from workflow.md" test "$(grep -cF "Never commit without the user's OK." "$FIXTURE/.claude/rules/workflow.md")" = 0
check "refresh: workflow.md outside sentinels byte-identical" same_outside "$SNAP/.claude/rules/workflow.md" "$FIXTURE/.claude/rules/workflow.md"
check "refresh: CLAUDE.md untouched (app table + hand-written notes)" cmp -s "$SNAP/CLAUDE.md" "$FIXTURE/CLAUDE.md"
check "refresh: pitfalls.md untouched (entry preserved)" cmp -s "$SNAP/.claude/rules/pitfalls.md" "$FIXTURE/.claude/rules/pitfalls.md"
check "refresh: architecture.md untouched (Test layout row preserved)" cmp -s "$SNAP/.claude/rules/architecture.md" "$FIXTURE/.claude/rules/architecture.md"
check "refresh: rules/api/commands.md untouched" cmp -s "$SNAP/.claude/rules/api/commands.md" "$FIXTURE/.claude/rules/api/commands.md"
check "refresh: conventions.json untouched" cmp -s "$SNAP/.claude/conventions.json" "$FIXTURE/.claude/conventions.json"
check "refresh: knowledge.md keeps its former content first" starts_with "$SNAP/.claude/rules/knowledge.md" "$FIXTURE/.claude/rules/knowledge.md"
check "refresh: missing section appended with a notice" grep -qF '<!-- conventions:refresh — section knowledge.pitfalls was missing' "$FIXTURE/.claude/rules/knowledge.md"
check "refresh: appended section carries its sentinels and body" \
  test "$(grep -cF -e '<!-- conventions:begin knowledge.pitfalls -->' -e '<!-- conventions:end knowledge.pitfalls -->' -e 'under 40 lines' "$FIXTURE/.claude/rules/knowledge.md")" = 3

cp -R "$FIXTURE/.claude" "$TMP/refresh-after-claude"
refresh_run "refresh: second run → exit 0" 0 "$EDITED_TPL"
check "refresh: second run → no changed file" test ! -s "$LAST_STDOUT"
check "refresh: second run → workflow.md stable" cmp -s "$TMP/refresh-after-claude/rules/workflow.md" "$FIXTURE/.claude/rules/workflow.md"
check "refresh: second run → knowledge.md stable" cmp -s "$TMP/refresh-after-claude/rules/knowledge.md" "$FIXTURE/.claude/rules/knowledge.md"

# Files without sentinels are skipped; a section without its end marker is
# refused; a repo without conventions.json is refused.
printf '# Project CLAUDE.md\n\nKept as is, no sentinel.\n' >"$FIXTURE/CLAUDE.md"
cp "$FIXTURE/CLAUDE.md" "$TMP/claude-no-sentinel.md"
refresh_run "refresh: CLAUDE.md without sentinels → exit 0" 0 "$EDITED_TPL"
check "refresh: CLAUDE.md without sentinels untouched" cmp -s "$TMP/claude-no-sentinel.md" "$FIXTURE/CLAUDE.md"
rewrite "$FIXTURE/.claude/rules/workflow.md" grep -vF '<!-- conventions:end workflow.pr -->'
cp "$FIXTURE/.claude/rules/workflow.md" "$TMP/workflow-broken.md"
refresh_run "refresh: section without end marker → exit 1" 1 "$EDITED_TPL"
check "refresh: broken section named on stderr" grep -qF 'section workflow.pr has no end marker' "$LAST_STDERR"
check "refresh: broken file left untouched" cmp -s "$TMP/workflow-broken.md" "$FIXTURE/.claude/rules/workflow.md"
mkdir -p "$TMP/no-conventions-root"
FIXTURE="$TMP/no-conventions-root"
refresh_run "refresh: no conventions.json → exit 1" 1
check "refresh: missing conventions.json named on stderr" grep -qF '.claude/conventions.json missing' "$LAST_STDERR"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n'
if [ "$FAILED" -ne 0 ]; then
  printf 'FAILED: %d of %d assertions\n' "$FAILED" "$((PASSED + FAILED))"
  exit 1
fi
printf 'OK: %d assertions\n' "$PASSED"
