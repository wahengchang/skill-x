# shellcheck shell=bash
# Project survey: the one-shot, machine-derivable snapshot of a repository that
# x-discovery and x-plan-eng read instead of scanning the tree themselves.
#
# The point is token cost, not convenience. Both skills used to walk README,
# entry points, schemas, configuration, tests and git log independently, so the
# same 100-300 KB landed in the agent's context twice. Everything here is a fact
# a script can produce, so the agent spends its context on judgement and on the
# few files it actually needs to read closely.
#
# The output is capped (X_SURVEY_MAX_BYTES). An uncapped survey would just move
# the cost from "scan the repo" to "read the survey", so every section is
# top-N bounded and the whole document is truncated as a last resort.

# Bump when the emitted sections change: the version is part of the cache key,
# so an upgraded xdh rebuilds a survey written by an older one.
X_SURVEY_SCHEMA=2
X_SURVEY_MAX_BYTES=8192

x_survey_dir() { x_resolve_paths; printf '%s' "$X_RUNTIME/survey"; }
x_survey_file() { printf '%s' "$(x_survey_dir)/survey.md"; }
x_survey_keyfile() { printf '%s' "$(x_survey_dir)/survey.key"; }

# SHA-256 of stdin. Mirrors lib/plan.sh's fallback chain rather than adding a
# second hashing path to the codebase.
x_survey_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    x_die "survey: sha256 unavailable"
  fi
}

# Cache key: commit + working-tree state + schema version. A committed change
# moves HEAD; an uncommitted one moves the porcelain digest. Both rebuild.
x_survey_key() {
  local head porcelain
  head=$(git rev-parse HEAD 2>/dev/null || printf 'no-head')
  # .dev-hub is execution residue, not project content (ARCHITECTURE decision
  # #13). It also has to be excluded for correctness: in a repository that has
  # not run `xdh init` the directory is merely untracked, so writing the survey
  # into it changes `git status` and the cache key would invalidate itself on
  # every single call.
  # `grep -v` exits 1 when every line was filtered out, which is the ordinary
  # case: a clean tree, or one whose only change is .dev-hub itself. Today that
  # status is swallowed because `key=$(x_survey_key)` suppresses errexit inside
  # the substitution — an accident, not a design. A direct call to this function
  # dies on a clean repository, so make the empty case explicit.
  porcelain=$(git status --porcelain 2>/dev/null |
    { LC_ALL=C grep -v '\.dev-hub/' || true; } | x_survey_sha)
  printf 'schema=%s\nhead=%s\nporcelain=%s\n' "$X_SURVEY_SCHEMA" "$head" "$porcelain"
}

# Tracked files plus untracked-but-not-ignored ones, NUL-separated. Using git as
# the file source rather than find means .gitignore is honoured for free and the
# listing matches what a reviewer would consider part of the project.
x_survey_files() {
  {
    git ls-files -z 2>/dev/null || true
    git ls-files -z --others --exclude-standard 2>/dev/null || true
  } | LC_ALL=C sort -z -u | x_survey_exclude_runtime
}

# Drop .dev-hub from the listing: the survey describes the project, never the
# hub's own runtime state, and counting its own output would make consecutive
# surveys disagree.
x_survey_exclude_runtime() {
  local f
  while IFS= read -r -d '' f; do
    case $f in
      .dev-hub/*) ;;
      *) printf '%s\0' "$f" ;;
    esac
  done
}

# The subset of x_survey_files that `wc -l` can actually read. The repo tracks
# symlinks to directories (commands-src/*/scripts -> ../_x-shared/scripts), and
# wc exits non-zero on those; under `set -euo pipefail` that would abort the
# whole survey rather than skipping one path.
x_survey_regular_files() {
  local f
  while IFS= read -r -d '' f; do
    [[ -f $f && ! -L $f ]] && printf '%s\0' "$f"
  done < <(x_survey_files)
}

x_survey_section_repo() {
  local branch head_short tracked dirty
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')
  head_short=$(git rev-parse --short HEAD 2>/dev/null || printf 'none')
  tracked=$(x_survey_files | LC_ALL=C tr '\0' '\n' | LC_ALL=C grep -c . || true)
  dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
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
  counted=$(x_survey_regular_files | xargs -0 wc -l 2>/dev/null |
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
  rows=$(git log --format= --name-only -n 200 2>/dev/null |
    LC_ALL=C grep -v '^$' | LC_ALL=C grep -v '^\.dev-hub/' |
    LC_ALL=C sort | LC_ALL=C uniq -c |
    LC_ALL=C sort -rn | head -12 |
    LC_ALL=C awk '{ c = $1; $1 = ""; sub(/^ /, ""); printf "- %s — %s change(s)\n", $0, c }')
  if [[ -n $rows ]]; then printf '%s\n' "$rows"; else printf -- '- no history\n'; fi
  printf '\n'
}

# ---------------------------------------------------------------------------
# Code graph routing.
#
# CodeGraph (@colbymchenry/codegraph) answers "who calls this / what does this
# reach / which tests cover it" from an index instead of from reading files.
# Measured on two real projects, its plain-text answer to a callers question is
# 30-180x smaller than the files an agent would otherwise open to answer it.
#
# It only supports ~30 compiled/scripted languages — no shell, Markdown or YAML
# — so a repository like skill-x itself indexes almost nothing. That is the
# normal case, not an error: the survey classifies the project once and the
# skills route on the answer.
# ---------------------------------------------------------------------------

# Extensions CodeGraph 1.5 extracts structure from. Deliberately a subset of its
# advertised list: only what we would actually route on.
X_SURVEY_GRAPH_EXTS='ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|cs|php|rb|c|h|cc|cpp|hpp|m|swift|kt|kts|scala|dart|vue|svelte|astro|lua|sol|tf|nix'

# Hard bound on any codegraph call. A slow graph must never hold up planning:
# every call site degrades to the file route instead of waiting.
X_SURVEY_GRAPH_TIMEOUT=120

# Run codegraph with telemetry off and a hard timeout. The CLI reports
# "collects anonymous usage stats" on first use; a skill framework that runs
# over private repositories opts out rather than deciding that for the user.
x_survey_codegraph() {
  local t=timeout
  command -v timeout >/dev/null 2>&1 || t=""
  (
    cd -- "$X_MAIN_ROOT" || exit 1
    CODEGRAPH_TELEMETRY=0 ${t:+$t "$X_SURVEY_GRAPH_TIMEOUT"} codegraph "$@" 2>/dev/null
  )
}

# True when the project contains any file in a supported language.
#
# Deliberately a presence check, not a proportion. An earlier version required a
# supported-language *share* of the whole tree, which judged a project by how
# much of it is not code: a content system with 200 Markdown articles and 40
# TypeScript files scored 17% and was refused the graph, even though those 40
# files are precisely what a plan gets written against. The share also never
# decided anything on real repositories (measured: 62%, 65%, 0%) while carrying
# that false negative. Whether the graph is useful is answered by the index
# below, not by the article count.
x_survey_graph_has_code() {
  x_survey_files | LC_ALL=C tr '\0' '\n' |
    LC_ALL=C awk -v exts="$X_SURVEY_GRAPH_EXTS" '
      BEGIN { n = split(exts, a, "|"); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
      {
        name = $0
        sub(/^.*\//, "", name)
        if (name ~ /\./) { e = name; sub(/^.*\./, "", e); if (e in ok) { found = 1; exit } }
      }
      END { exit found ? 0 : 1 }
    '
}

# Classify the project and, when the graph is usable, keep it fresh.
# Sets X_SURVEY_GRAPH, X_SURVEY_NAV and X_SURVEY_GRAPH_SYMBOLS.
#
# `do_sync` is passed 1 only when the survey itself is rebuilding, i.e. when the
# commit or the working tree moved. The survey's cache key already asks exactly
# the question `codegraph sync` answers, so reusing it means no second staleness
# mechanism and no cost at all when nothing changed.
x_survey_graph_probe() {
  local do_sync=${1:-0} symbols
  X_SURVEY_GRAPH_SYMBOLS=0

  if ! command -v codegraph >/dev/null 2>&1; then X_SURVEY_GRAPH=absent; X_SURVEY_NAV=files; return 0; fi

  # Cheap pre-filter only: skip the tool entirely for a project with no code at
  # all. It is not a judgement about whether the graph is worth using.
  if ! x_survey_graph_has_code; then
    X_SURVEY_GRAPH=unsupported; X_SURVEY_NAV=files; return 0
  fi

  if [[ ! -d $X_MAIN_ROOT/.codegraph ]]; then
    X_SURVEY_GRAPH=uninitialized; X_SURVEY_NAV=files; return 0
  fi

  # A full `codegraph index` is never run from here. It is seconds on a small
  # project but minutes on a large one, and stalling a planning session for that
  # is worse than the cost this whole mechanism exists to remove.
  if (( do_sync )); then
    if ! x_survey_codegraph sync -q >/dev/null; then
      X_SURVEY_GRAPH=stale; X_SURVEY_NAV=files; return 0
    fi
  fi

  symbols=$(x_survey_codegraph status |
    LC_ALL=C awk '/^[ \t]*Nodes:/ { gsub(/[^0-9]/, "", $2); print $2; exit }' || true)
  [[ $symbols =~ ^[0-9]+$ ]] || symbols=0
  X_SURVEY_GRAPH_SYMBOLS=$symbols

  if (( symbols == 0 )); then
    X_SURVEY_GRAPH=empty; X_SURVEY_NAV=files; return 0
  fi

  X_SURVEY_GRAPH=ready; X_SURVEY_NAV=graph
}

# The glob `codegraph affected` needs in order to recognise this project's
# tests. Its default matches *.test.* / *.spec.* only, so a Python suite named
# test_*.py silently comes back empty — an empty answer that reads exactly like
# "nothing is affected". Deriving the glob here is what stops that.
x_survey_graph_test_glob() {
  local names
  names=$(x_survey_files | LC_ALL=C tr '\0' '\n')
  if printf '%s\n' "$names" | LC_ALL=C grep -qE '(^|/)test_[^/]*\.py$'; then
    printf '**/test_*.py'
  elif printf '%s\n' "$names" | LC_ALL=C grep -qE '_test\.go$'; then
    printf '**/*_test.go'
  elif printf '%s\n' "$names" | LC_ALL=C grep -qE '\.(test|spec)\.[jt]sx?$'; then
    printf '**/*.{test,spec}.{ts,tsx,js,jsx}'
  else
    printf ''
  fi
}

# Written only when the graph is usable. Deliberately thin: readiness, the test
# glob, and the command menu. An earlier version also probed the most
# depended-on symbols, which meant 40 sequential `codegraph callers` processes
# and took ~11s on a 353-file project — far too much for something that runs on
# every rebuild, and the wrong shape besides. Fan-in is a question to ask about
# the symbols a task actually touches, which is what the skills now do.
x_survey_section_graph() {
  [[ ${X_SURVEY_GRAPH:-} == ready ]] || return 0
  printf '## Code graph\n\n'
  printf -- '- Index: ready, %s nodes\n' "$X_SURVEY_GRAPH_SYMBOLS"

  local glob
  glob=$(x_survey_graph_test_glob || true)
  if [[ -n $glob ]]; then
    printf -- '- `affected` needs this test glob here: `-f "%s"`\n' "$glob"
  fi
  printf '\n'

  printf 'Ask the graph before opening files:\n\n'
  printf '```bash\n'
  printf 'codegraph callers <symbol>   # who calls it, by name and file:line\n'
  printf 'codegraph callees <symbol>   # what it depends on\n'
  printf 'codegraph impact  <symbol>   # transitive blast radius (-d for depth)\n'
  printf '```\n\n'
  printf 'Plain output, not `--json`: the JSON envelope is about twice the bytes and\n'
  printf 'carries the same facts. Open files only for the few symbols these point at.\n\n'
}

x_survey_render() {
  printf '<!-- Generated by `xdh survey`. Machine-derived facts only: no judgement, no prose.\n'
  printf '     Read this instead of walking the tree. Open individual files only where a\n'
  printf '     decision actually depends on their contents. -->\n\n'
  printf '# Project survey\n\n'
  x_survey_section_repo
  x_survey_section_layout
  x_survey_section_types
  x_survey_section_entry
  x_survey_section_docs
  x_survey_section_tests
  x_survey_section_devex
  x_survey_section_graph
  x_survey_section_hotspots
}

# Last-resort cap. Sections are individually bounded, so this should not fire on
# an ordinary repository; when it does, a truncated survey with an explicit
# marker beats silently handing the agent an unbounded document.
x_survey_truncate() {
  local file=$1 bytes
  bytes=$(wc -c < "$file" | tr -d ' ')
  (( bytes <= X_SURVEY_MAX_BYTES )) && return 0
  local keep=$(( X_SURVEY_MAX_BYTES - 80 ))
  {
    dd if="$file" bs=1 count="$keep" 2>/dev/null
    printf '\n\n<!-- survey truncated at %s bytes -->\n' "$X_SURVEY_MAX_BYTES"
  } | x_atomic_write "$file"
}

x_survey_ensure() {
  local force=0
  while (( $# )); do
    case $1 in
      --force) force=1; shift ;;
      *) x_die "survey ensure: unknown option '$1'" ;;
    esac
  done

  x_ensure_dev_hub
  local dir file keyfile key state
  dir=$(x_survey_dir); file=$(x_survey_file); keyfile=$(x_survey_keyfile)
  mkdir -p "$dir"
  key=$(x_survey_key)

  if (( ! force )) && [[ -f $file && -f $keyfile ]] && [[ $(cat -- "$keyfile") == "$key" ]]; then
    state=fresh
    # Nothing moved, so the graph cannot have gone stale either: probe without
    # paying for a sync.
    x_survey_graph_probe 0
  else
    # Rebuilding means the commit or the working tree moved — the one moment a
    # sync is worth its cost. It runs before the render so the Code graph
    # section reports post-sync numbers.
    x_survey_graph_probe 1
    x_survey_render | x_atomic_write "$file"
    x_survey_truncate "$file"
    printf '%s' "$key" | x_atomic_write "$keyfile"
    state=rebuilt
  fi

  x_emit X_SURVEY_FILE "$file"
  x_emit X_SURVEY_STATE "$state"
  x_emit X_SURVEY_HEAD "$(git rev-parse HEAD 2>/dev/null || printf 'no-head')"
  x_emit X_SURVEY_BYTES "$(wc -c < "$file" | tr -d ' ')"
  x_emit X_SURVEY_NAV "${X_SURVEY_NAV:-files}"
  x_emit X_SURVEY_GRAPH "${X_SURVEY_GRAPH:-absent}"
  x_emit X_SURVEY_GRAPH_SYMBOLS "${X_SURVEY_GRAPH_SYMBOLS:-0}"
}

# Report where the survey lives without building it, so a caller can decide
# whether to spend the rebuild.
x_survey_path() {
  x_resolve_paths
  local file
  file=$(x_survey_file)
  x_emit X_SURVEY_FILE "$file"
  if [[ -f $file ]]; then
    x_emit X_SURVEY_STATE "$([[ $(cat -- "$(x_survey_keyfile)" 2>/dev/null) == "$(x_survey_key)" ]] && printf fresh || printf stale)"
    x_emit X_SURVEY_BYTES "$(wc -c < "$file" | tr -d ' ')"
  else
    x_emit X_SURVEY_STATE absent
    x_emit X_SURVEY_BYTES 0
  fi
  # Report-only: never syncs, so a caller can ask what state things are in
  # without paying for anything.
  x_survey_graph_probe 0
  x_emit X_SURVEY_NAV "${X_SURVEY_NAV:-files}"
  x_emit X_SURVEY_GRAPH "${X_SURVEY_GRAPH:-absent}"
}
