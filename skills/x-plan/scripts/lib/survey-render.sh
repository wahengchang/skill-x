x_survey_section_repo() {
  local branch head_short tracked dirty
  branch=$(git -C "$X_MAIN_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')
  head_short=$(git -C "$X_MAIN_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'none')
  tracked=$(x_survey_files | LC_ALL=C tr '\0' '\n' | LC_ALL=C grep -c . || true)
  dirty=$(git -C "$X_MAIN_ROOT" status --porcelain 2>/dev/null |
    LC_ALL=C grep -vE '^.. \.codegraph(/|$)' | wc -l | tr -d ' ')
  printf '## Repository\n\n'
  printf -- '- Root: %s\n' "$(basename -- "$X_MAIN_ROOT")"
  printf -- '- Branch: %s (at %s)\n' "$branch" "$head_short"
  printf -- '- Files in scope: %s (%s uncommitted change(s))\n\n' "$tracked" "$dirty"
}

# Directory tree to depth 3, with per-directory file and line counts. Files are
# bucketed into their nearest ancestor at or above the depth limit, so a deep
# tree still accounts for every line somewhere.
x_survey_section_layout() {
  local counted
  counted=$(x_survey_regular_files |
    (cd -- "$X_MAIN_ROOT" && xargs -0 wc -l 2>/dev/null) |
    LC_ALL=C awk '
      $0 ~ /[ \t]total$/ { next }
      NF >= 2 {
        lines = $1
        path = $0
        sub(/^[ \t]*[0-9]+[ \t]+/, "", path)
        n = split(path, parts, "/")
        if (n == 1) { key = "." }
        else {
          depth = (n - 1 < 3) ? n - 1 : 3
          key = parts[1]
          for (i = 2; i <= depth; i++) key = key "/" parts[i]
        }
        files[key]++
        loc[key] += lines
      }
      END { for (k in files) printf "%d\t%d\t%s\n", files[k], loc[k], k }
    ' | LC_ALL=C sort -rn | head -25)

  printf '## Layout (top 25 directories, depth 3)\n\n'
  printf '| Directory | Files | Lines |\n|---|---:|---:|\n'
  printf '%s\n' "$counted" | LC_ALL=C awk -F'\t' 'NF == 3 { printf "| %s | %s | %s |\n", $3, $1, $2 }'
  printf '\n'
}

x_survey_section_types() {
  printf '## File types (top 12)\n\n'
  x_survey_files | LC_ALL=C tr '\0' '\n' | LC_ALL=C awk '
      {
        name = $0
        sub(/^.*\//, "", name)
        if (name ~ /\./) { ext = name; sub(/^.*\./, "", ext) } else { ext = "(none)" }
        n[ext]++
      }
      END { for (e in n) printf "%d\t%s\n", n[e], e }
    ' | LC_ALL=C sort -rn | head -12 |
    LC_ALL=C awk -F'\t' '{ printf "- %s%s — %s\n", ($2 == "(none)" ? "" : "."), $2, $1 }'
  printf '\n'
}

# Entry points a newcomer would look for first. Every candidate is reported with
# the file it came from, so the agent can open exactly that file and nothing else.
x_survey_section_entry() {
  printf '## Entry points\n\n'
  local found=0
  if [[ -f $X_MAIN_ROOT/package.json ]]; then
    local pkg
    pkg=$(LC_ALL=C awk '
      /"(main|module|types)"[ \t]*:/ { gsub(/[",]/, ""); sub(/^[ \t]+/, ""); print "- package.json " $0 }
    ' "$X_MAIN_ROOT/package.json" | head -5)
    [[ -n $pkg ]] && { printf '%s\n' "$pkg"; found=1; }
  fi
  local candidates
  candidates=$(x_survey_files | LC_ALL=C tr '\0' '\n' | LC_ALL=C awk '
      { n = split($0, p, "/") }
      n <= 2 && $0 ~ /(^|\/)(main|index|app|cli|server|__main__)\.[a-z]+$/ { print "- " $0 }
      $0 ~ /^bin\/[^\/]+$/ { print "- " $0 }
    ' | head -12)
  [[ -n $candidates ]] && { printf '%s\n' "$candidates"; found=1; }
  (( found )) || printf -- '- none detected mechanically; identify from the docs below\n'
  printf '\n'
}

x_survey_section_docs() {
  printf '## Docs\n\n'
  local docs
  docs=$(x_survey_files | LC_ALL=C tr '\0' '\n' | LC_ALL=C awk '
      $0 ~ /^(README|ARCHITECTURE|CONTRIBUTING|AGENTS|CLAUDE|CHANGELOG)[^\/]*$/ { print "- " $0 }
      $0 ~ /^docs\// { print "- " $0 }
    ' | head -15)
  if [[ -n $docs ]]; then printf '%s\n' "$docs"; else printf -- '- none\n'; fi
  printf '\n'
}

x_survey_section_tests() {
  printf '## Tests\n\n'
  local rows
  rows=$(x_survey_files | LC_ALL=C tr '\0' '\n' | LC_ALL=C awk '
      $0 ~ /(^|\/)(tests?|spec|__tests__)\// || $0 ~ /(_test|_spec|\.test|\.spec)\.[a-z]+$/ {
        dir = $0
        sub(/\/[^\/]*$/, "", dir)
        if (dir == $0) dir = "."
        n[dir]++
      }
      END { for (d in n) printf "%d\t%s\n", n[d], d }
    ' | LC_ALL=C sort -rn | head -10 |
    LC_ALL=C awk -F'\t' '{ printf "- %s — %s file(s)\n", $2, $1 }')
  if [[ -n $rows ]]; then printf '%s\n' "$rows"; else printf -- '- none detected\n'; fi
  printf '\n'
}

# The developer journey, as far as it is mechanically knowable. This is what the
# DevEx facet used to reconstruct by hand for every single work item; collected
# once here, a work item only has to say whether it touches any of it.
x_survey_section_devex() {
  printf '## DevEx commands\n\n'
  local found=0 out
  if [[ -f $X_MAIN_ROOT/Makefile ]]; then
    out=$(LC_ALL=C awk '
      /^[a-zA-Z0-9_][a-zA-Z0-9_.-]*:([^=]|$)/ { t = $0; sub(/:.*$/, "", t); print "- make " t }
    ' "$X_MAIN_ROOT/Makefile" | head -12)
    [[ -n $out ]] && { printf '%s\n' "$out"; found=1; }
  fi
  if [[ -f $X_MAIN_ROOT/package.json ]]; then
    out=$(LC_ALL=C awk '
      /"scripts"[ \t]*:/ { inse = 1; next }
      inse && /^[ \t]*\}/ { inse = 0 }
      inse && /:/ { k = $0; sub(/^[ \t]*"/, "", k); sub(/".*$/, "", k); if (k != "") print "- npm run " k }
    ' "$X_MAIN_ROOT/package.json" | head -12)
    [[ -n $out ]] && { printf '%s\n' "$out"; found=1; }
  fi
  out=$(x_survey_files | LC_ALL=C tr '\0' '\n' |
    { LC_ALL=C grep -E '^\.github/workflows/.*\.ya?ml$' 2>/dev/null || true; } | head -5 |
    while IFS= read -r wf; do
      [[ -f $X_MAIN_ROOT/$wf ]] || continue
      printf -- '- CI %s: ' "$wf"
      LC_ALL=C awk '
        /^[ \t]*run:[ \t]*/ { s = $0; sub(/^[ \t]*run:[ \t]*/, "", s); if (s != "" && s !~ /^\|/) print s }
      ' "$X_MAIN_ROOT/$wf" | head -4 | paste -sd';' -
    done)
  [[ -n $out ]] && { printf '%s\n' "$out"; found=1; }
  (( found )) || printf -- '- none detected mechanically\n'
  printf '\n'
}

x_survey_section_hotspots() {
  printf '## Change hotspots (last 200 commits)\n\n'
  local rows
  rows=$(git -C "$X_MAIN_ROOT" log --format= --name-only -n 200 2>/dev/null |
    LC_ALL=C grep -v '^$' | LC_ALL=C grep -vE '^(\.dev-hub|\.codegraph)/' |
    LC_ALL=C sort | LC_ALL=C uniq -c |
    LC_ALL=C sort -rn | head -12 |
    LC_ALL=C awk '{ c = $1; $1 = ""; sub(/^ /, ""); printf "- %s — %s change(s)\n", $0, c }')
  if [[ -n $rows ]]; then printf '%s\n' "$rows"; else printf -- '- no history\n'; fi
  printf '\n'
}

# ---------------------------------------------------------------------------
# Code graph routing.
