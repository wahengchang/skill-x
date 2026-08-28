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
X_SURVEY_GRAPH_TIMEOUT=${X_SURVEY_GRAPH_TIMEOUT:-120}

# Run codegraph with telemetry off and a hard timeout. GNU `timeout` is not part
# of stock macOS, so prefer it when present, then Homebrew's `gtimeout`, then the
# system Perl alarm. If none exists, fail closed to the file route instead of
# running an unbounded graph command.
x_survey_codegraph() {
  (
    cd -- "$X_MAIN_ROOT" || exit 1
    if command -v timeout >/dev/null 2>&1; then
      CODEGRAPH_TELEMETRY=0 timeout "$X_SURVEY_GRAPH_TIMEOUT" codegraph "$@" 2>/dev/null
    elif command -v gtimeout >/dev/null 2>&1; then
      CODEGRAPH_TELEMETRY=0 gtimeout "$X_SURVEY_GRAPH_TIMEOUT" codegraph "$@" 2>/dev/null
    elif command -v perl >/dev/null 2>&1; then
      CODEGRAPH_TELEMETRY=0 perl -e 'my $t = shift; alarm($t); exec @ARGV or exit 127' \
        "$X_SURVEY_GRAPH_TIMEOUT" codegraph "$@" 2>/dev/null
    else
      return 1
    fi
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
# commit or working content moved. The survey's cache key asks exactly the
# question `codegraph sync` answers, so no second staleness mechanism is needed.
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

# Graph freshness is part of the cached survey result. In particular, a failed
# sync must stay `stale/files` on later cache hits; re-running only `status`
# would see a non-empty old index and incorrectly promote it back to `graph`.
x_survey_graph_save() {
  local file
  file=$(x_survey_graphfile)
  printf 'graph=%s\nnav=%s\nsymbols=%s\n' \
    "${X_SURVEY_GRAPH:-absent}" "${X_SURVEY_NAV:-files}" "${X_SURVEY_GRAPH_SYMBOLS:-0}" |
    x_atomic_write "$file"
}

x_survey_graph_load() {
  local file graph nav symbols
  file=$(x_survey_graphfile)
  [[ -f $file ]] || return 1
  graph=$(sed -n 's/^graph=//p' "$file")
  nav=$(sed -n 's/^nav=//p' "$file")
  symbols=$(sed -n 's/^symbols=//p' "$file")
  case $graph in absent|unsupported|uninitialized|empty|stale|ready) ;; *) return 1 ;; esac
  case $nav in files|graph) ;; *) return 1 ;; esac
  [[ $symbols =~ ^[0-9]+$ ]] || return 1
  [[ $graph == ready && $nav == graph || $graph != ready && $nav == files ]] || return 1
  X_SURVEY_GRAPH=$graph
  X_SURVEY_NAV=$nav
  X_SURVEY_GRAPH_SYMBOLS=$symbols
}

# A cached ready graph may disappear between calls (tool removed or index
# deleted). Downgrade it if so, but never promote a cached non-ready state on a
# cache hit: only a rebuild/--force may establish freshness after sync.
x_survey_graph_validate_cached() {
  [[ ${X_SURVEY_GRAPH:-} == ready ]] || return 0
  local cached_symbols=${X_SURVEY_GRAPH_SYMBOLS:-0}
  x_survey_graph_probe 0
  if [[ ${X_SURVEY_GRAPH:-} == ready ]]; then
    # Node count is informational; the survey file was rendered with the cached
    # count, so keep that stable until the next rebuild.
    X_SURVEY_GRAPH_SYMBOLS=$cached_symbols
  fi
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

