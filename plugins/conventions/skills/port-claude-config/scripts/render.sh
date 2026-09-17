#!/usr/bin/env bash
# render.sh <template> <conventions.json> [--app-table <file>] [--permissions <file>]
# Prints <template> with every {{PLACEHOLDER}} substituted from the conventions
# file (contracts/templates.md):
#   INTEGRATION_BRANCH  .integrationBranch (required)
#   PRODUCTION_BRANCH   .productionBranch, default main
#   PKG_MANAGER         .packageManager (required when the template uses it)
#   PKG_EXACT_FLAG      derived from PKG_MANAGER: pnpm -E, npm --save-exact,
#                       yarn --exact, bun --exact
#   FORMATTER           .formatter, default none
#   PR_SIZE_LINES/FILES/LABEL  .prSize.{lines,files,label}, defaults 400/15/large-pr
#   ADR_DIR             .adrDir, default docs/adr
#   DEPLOY_NOTE         " (<.deployNote>)" when the key is set, else ""
#   APP_TABLE           the content of --app-table <file>
#   PERMISSIONS         the content of --permissions <file> (a JSON array)
# A placeholder whose value is missing, or any {{NAME}} not in this list, is
# reported on stderr by name and the script exits 1 without printing the page.
set -euo pipefail

usage() {
  printf 'usage: render.sh <template> <conventions.json> [--app-table <file>] [--permissions <file>]\n' >&2
  exit 1
}

if [ "$#" -lt 2 ]; then
  usage
fi
template="$1"
conventions="$2"
shift 2
app_table_file=""
permissions_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app-table)
      [ "$#" -ge 2 ] || usage
      app_table_file="$2"
      shift 2
      ;;
    --permissions)
      [ "$#" -ge 2 ] || usage
      permissions_file="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

if [ ! -f "$template" ]; then
  printf 'render: template not found: %s\n' "$template" >&2
  exit 1
fi
if [ ! -f "$conventions" ] || ! jq -e 'type == "object"' "$conventions" >/dev/null 2>&1; then
  printf 'render: conventions file missing or not a JSON object: %s\n' "$conventions" >&2
  exit 1
fi

# conv <jq-path> <default> — prints the string value at <jq-path> or <default>.
conv() {
  jq -r --arg d "$2" "($1) // \$d | tostring" "$conventions"
}

integration="$(conv .integrationBranch "")"
production="$(conv .productionBranch main)"
pkg_manager="$(conv .packageManager "")"
formatter="$(conv .formatter none)"
pr_lines="$(conv .prSize.lines 400)"
pr_files="$(conv .prSize.files 15)"
pr_label="$(conv .prSize.label large-pr)"
adr_dir="$(conv .adrDir docs/adr)"
deploy_note="$(conv .deployNote "")"
if [ -n "$deploy_note" ]; then
  deploy_note=" ($deploy_note)"
fi
exact_flag=""
case "$pkg_manager" in
  pnpm) exact_flag="-E" ;;
  npm) exact_flag="--save-exact" ;;
  yarn | bun) exact_flag="--exact" ;;
esac
app_table=""
if [ -n "$app_table_file" ]; then
  if [ ! -f "$app_table_file" ]; then
    printf 'render: --app-table file not found: %s\n' "$app_table_file" >&2
    exit 1
  fi
  app_table="$(cat "$app_table_file")"
fi
permissions=""
if [ -n "$permissions_file" ]; then
  if ! jq -e 'type == "array"' "$permissions_file" >/dev/null 2>&1; then
    printf 'render: --permissions file must be a JSON array: %s\n' "$permissions_file" >&2
    exit 1
  fi
  permissions="$(jq -c . "$permissions_file")"
fi

content="$(cat "$template"; printf x)"
content="${content%x}"

# substitute <NAME> <value> — replaces every {{NAME}} in content; an empty
# value counts as unresolved so the final check names it. DEPLOY_NOTE is the
# one placeholder that legitimately resolves to nothing.
substitute() {
  local name="$1" value="$2"
  if [ -z "$value" ] && [ "$name" != "DEPLOY_NOTE" ]; then
    return 0
  fi
  content="${content//"{{$name}}"/$value}"
}

substitute INTEGRATION_BRANCH "$integration"
substitute PRODUCTION_BRANCH "$production"
substitute PKG_MANAGER "$pkg_manager"
substitute PKG_EXACT_FLAG "$exact_flag"
substitute FORMATTER "$formatter"
substitute PR_SIZE_LINES "$pr_lines"
substitute PR_SIZE_FILES "$pr_files"
substitute PR_SIZE_LABEL "$pr_label"
substitute ADR_DIR "$adr_dir"
substitute DEPLOY_NOTE "$deploy_note"
substitute APP_TABLE "$app_table"
substitute PERMISSIONS "$permissions"

unresolved="$(printf '%s' "$content" | grep -oE '\{\{[A-Z_]+\}\}' | sort -u || true)"
if [ -n "$unresolved" ]; then
  while IFS= read -r name; do
    printf 'render: unresolved placeholder %s in %s\n' "$name" "$template" >&2
  done <<<"$unresolved"
  exit 1
fi

printf '%s' "$content"
