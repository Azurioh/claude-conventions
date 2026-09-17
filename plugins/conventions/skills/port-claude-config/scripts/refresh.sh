#!/usr/bin/env bash
# refresh.sh <target-root> — re-applies the template-owned sections of a
# ported repository (contracts/templates.md, "Refresh").
#
# For every template that carries sentinel sections (CLAUDE.md, rules/*.md)
# and whose target file exists in <target-root>:
#   1. the template's sentinel blocks are extracted and rendered with the
#      target's .claude/conventions.json (render.sh) — only the placeholders
#      inside the blocks need a value, so {{APP_TABLE}} and everything else
#      outside the sentinels is never involved;
#   2. in the target file, the body between each matching
#      <!-- conventions:begin <id> --> … <!-- conventions:end <id> --> pair is
#      replaced by the rendered body; every other byte stays as it is;
#   3. a section present in the template but absent from the file is appended
#      at the end, preceded by a one-line notice comment.
# A target file without any sentinel is skipped, as are templates without
# sentinels (commands.md, settings.json, conventions.json, gitignore) and the
# per-app directories .claude/rules/<app>/. The paths of the files that changed
# are printed on stdout, one per line; exit 0 also when nothing changed.
# CONVENTIONS_TEMPLATES_DIR overrides the templates directory (tests).
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: refresh.sh <target-root>\n' >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="${CONVENTIONS_TEMPLATES_DIR:-$SCRIPT_DIR/../templates}"
RENDER="$SCRIPT_DIR/render.sh"

root="$1"
if [ ! -d "$root" ]; then
  printf 'refresh: target root not found: %s\n' "$root" >&2
  exit 1
fi
root="$(cd "$root" && pwd)"
conventions="$root/.claude/conventions.json"
if [ ! -f "$conventions" ]; then
  printf 'refresh: %s missing — run /conventions:port-claude-config first\n' ".claude/conventions.json" >&2
  exit 1
fi
if [ ! -d "$TEMPLATES" ]; then
  printf 'refresh: templates directory not found: %s\n' "$TEMPLATES" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'find "$WORK" -depth -delete' EXIT

# has_sentinel <file> — true when the file opens at least one section.
has_sentinel() {
  grep -q '^<!-- conventions:begin [^ ]* -->$' "$1"
}

# extract_sections <file> — prints every sentinel block of <file> (begin line,
# body, end line), in file order, nothing else.
extract_sections() {
  awk '
    $1 == "<!--" && $2 == "conventions:begin" && $4 == "-->" && NF == 4 { inside = 1 }
    inside { print }
    $1 == "<!--" && $2 == "conventions:end" && $4 == "-->" && NF == 4 { inside = 0 }
  ' "$1"
}

# merge_sections <rendered-sections> <target> — prints <target> with the body
# of every section known from <rendered-sections> replaced, and the sections
# the target lacks appended after a notice line. Exits 3 when a section of the
# target has no end marker (the file is left for a human to fix).
merge_sections() {
  awk '
    function is_begin() { return $1 == "<!--" && $2 == "conventions:begin" && $4 == "-->" && NF == 4 }
    function is_end() { return $1 == "<!--" && $2 == "conventions:end" && $4 == "-->" && NF == 4 }
    FNR == NR {
      if (is_begin()) { current = $3; order[++count] = current; body[current] = ""; next }
      if (is_end()) { current = ""; next }
      if (current != "") { body[current] = body[current] $0 "\n" }
      next
    }
    skipping != "" {
      if (is_end() && $3 == skipping) { print; skipping = "" }
      next
    }
    is_begin() && ($3 in body) {
      print
      printf "%s", body[$3]
      seen[$3] = 1
      skipping = $3
      next
    }
    { print }
    END {
      if (skipping != "") {
        printf "refresh: section %s has no end marker in %s\n", skipping, FILENAME > "/dev/stderr"
        exit 3
      }
      for (i = 1; i <= count; i++) {
        id = order[i]
        if (id in seen) { continue }
        printf "\n<!-- conventions:refresh — section %s was missing from this file and has been appended; move it where it belongs -->\n", id
        printf "<!-- conventions:begin %s -->\n%s<!-- conventions:end %s -->\n", id, body[id], id
      }
    }
  ' "$1" "$2"
}

# refresh_file <template> <target-relative-path> — runs the three steps on one
# file and prints the relative path when the target changed.
refresh_file() {
  local template="$1" rel="$2" target sections rendered merged
  target="$root/$rel"
  if [ ! -f "$target" ]; then
    return 0
  fi
  if ! has_sentinel "$template" || ! has_sentinel "$target"; then
    return 0
  fi
  sections="$WORK/$(basename "$template")"
  rendered="$WORK/rendered.md"
  merged="$WORK/merged.md"
  extract_sections "$template" >"$sections"
  if ! "$RENDER" "$sections" "$conventions" >"$rendered"; then
    printf 'refresh: cannot render %s — fix .claude/conventions.json and retry\n' "$rel" >&2
    exit 1
  fi
  if ! merge_sections "$rendered" "$target" >"$merged"; then
    exit 1
  fi
  if ! cmp -s "$merged" "$target"; then
    cp "$merged" "$target"
    printf '%s\n' "$rel"
    CHANGED=$((CHANGED + 1))
  fi
}

CHANGED=0
refresh_file "$TEMPLATES/CLAUDE.md" "CLAUDE.md"
for template in "$TEMPLATES"/rules/*.md; do
  refresh_file "$template" ".claude/rules/$(basename "$template")"
done

if [ "$CHANGED" -eq 0 ]; then
  printf 'refresh: nothing to change\n' >&2
fi
