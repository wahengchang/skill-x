#!/usr/bin/env bash
# Focused regressions for PR #44 survey cache correctness. These cases exercise
# states that a status-only key and a cache-hit graph probe can silently get
# wrong without breaking the broader survey happy-path suite.
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(cd -- "$(mktemp -d "${TMPDIR:-/tmp}/skill-x-survey-cache.XXXXXX")" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT

export SKILL_X_OPENCODE_VERSION=v1

# shellcheck source=lib/harness.sh
source "$PROJECT_ROOT/tests/lib/harness.sh"
skill_x_test_parse_args "$@"

survey_kv() { sed -n "s/^$2=//p" "$1"; }

make_repo() {
  local repo=$1
  mkdir -p "$repo/src" "$repo/tests"
  git init -q -b main "$repo"
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name 'Test Runner'
  printf '# Demo\n' > "$repo/README.md"
  printf 'export const value = 1\n' > "$repo/src/app.ts"
  printf 'test("app", () => {})\n' > "$repo/tests/app.test.ts"
  git -C "$repo" add -A
  git -C "$repo" commit -qm initial
}

test_cache_tracks_content_first_run_and_subdirectory_scope() {
  local project="$TEST_ROOT/cache" repo="$TEST_ROOT/cache-repo"
  copy_built_project "$project"
  make_repo "$repo"
  local XDH="$project/commands/x-discovery/scripts/xdh"

  # `survey ensure` is allowed to be the first xdh command. Its own runtime must
  # be ignored before the cache is written and must never appear as project dirt.
  ( cd "$repo" && "$XDH" survey ensure ) > "$project/first"
  [[ $(survey_kv "$project/first" X_SURVEY_STATE) == rebuilt ]]
  local entry
  for entry in '.dev-hub/active/' '.dev-hub/worktrees/' '.dev-hub/runtime/'; do
    grep -Fxq "$entry" "$repo/.gitignore" || {
      echo "missing runtime ignore entry: $entry" >&2
      return 1
    }
  done
  if git -C "$repo" status --porcelain | rg -q '\.dev-hub'; then
    echo 'survey runtime leaked into git status' >&2
    return 1
  fi

  # A second edit to a path that is already dirty keeps the same porcelain
  # status (` M src/app.ts`) but changes content. The cache must rebuild anyway.
  printf 'export const second = 2\n' >> "$repo/src/app.ts"
  ( cd "$repo" && "$XDH" survey ensure ) > "$project/dirty1"
  [[ $(survey_kv "$project/dirty1" X_SURVEY_STATE) == rebuilt ]]
  ( cd "$repo" && "$XDH" survey ensure ) > "$project/fresh"
  [[ $(survey_kv "$project/fresh" X_SURVEY_STATE) == fresh ]]
  printf 'export const third = 3\n' >> "$repo/src/app.ts"
  ( cd "$repo" && "$XDH" survey ensure ) > "$project/dirty2"
  [[ $(survey_kv "$project/dirty2" X_SURVEY_STATE) == rebuilt ]] || {
    echo 'editing an already-dirty file did not invalidate the survey' >&2
    return 1
  }

  # `git ls-files` is cwd-sensitive. Running from src/ must still survey the
  # repository root, including root docs and sibling tests.
  ( cd "$repo/src" && "$XDH" survey ensure --force ) > "$project/subdir"
  local file
  file=$(survey_kv "$project/subdir" X_SURVEY_FILE)
  rg -qF 'README.md' "$file" || { echo 'root README missing from subdir survey' >&2; return 1; }
  rg -qF 'tests — 1 file(s)' "$file" || { echo 'sibling tests missing from subdir survey' >&2; return 1; }
}

make_codegraph_stub() {
  local bindir=$1
  mkdir -p "$bindir"
  cat > "$bindir/codegraph" <<'EOF_STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CODEGRAPH_STUB_LOG"
case ${1:-} in
  sync)
    [[ -f $CODEGRAPH_STUB_OK ]] || exit 1
    # Simulate the real index mutating its own untracked runtime during sync.
    mkdir -p .codegraph
    printf '%s\n' "$(date +%s)" > .codegraph/index-state
    ;;
  status)
    printf 'Index Statistics:\n  Files:     3\n  Nodes:     42\n  Edges:     8\n'
    ;;
esac
EOF_STUB
  chmod +x "$bindir/codegraph"
}

run_graph_survey() {
  local repo=$1 xdh=$2 bindir=$3 out=$4; shift 4
  ( cd "$repo" && PATH="$bindir:$PATH" \
      CODEGRAPH_STUB_LOG="$bindir/stub.log" CODEGRAPH_STUB_OK="$bindir/sync-ok" \
      "$xdh" survey ensure "$@" ) > "$out"
}

test_failed_graph_sync_stays_degraded_and_index_is_not_cache_input() {
  local project="$TEST_ROOT/graph" repo="$TEST_ROOT/graph-repo" bin="$TEST_ROOT/graph-bin"
  copy_built_project "$project"
  make_repo "$repo"
  mkdir -p "$repo/.codegraph"
  make_codegraph_stub "$bin"
  local XDH="$project/commands/x-discovery/scripts/xdh"

  # First rebuild cannot refresh the index, so it must degrade to files.
  run_graph_survey "$repo" "$XDH" "$bin" "$project/failed"
  [[ $(survey_kv "$project/failed" X_SURVEY_GRAPH) == stale ]]
  [[ $(survey_kv "$project/failed" X_SURVEY_NAV) == files ]]
  [[ $(rg -c '^sync' "$bin/stub.log" || true) -eq 1 ]]

  # A cache hit must preserve that freshness decision. `status` alone cannot
  # prove a non-empty old index is current, so there should be no graph call.
  run_graph_survey "$repo" "$XDH" "$bin" "$project/cached"
  [[ $(survey_kv "$project/cached" X_SURVEY_STATE) == fresh ]]
  [[ $(survey_kv "$project/cached" X_SURVEY_GRAPH) == stale ]]
  [[ $(survey_kv "$project/cached" X_SURVEY_NAV) == files ]]
  [[ $(wc -l < "$bin/stub.log" | tr -d ' ') -eq 1 ]] || {
    echo 'cache hit re-probed a stale graph' >&2
    return 1
  }

  # Explicit retry succeeds. The stub mutates .codegraph during sync; that
  # generated index is not project content and must not invalidate the cache.
  : > "$bin/sync-ok"
  run_graph_survey "$repo" "$XDH" "$bin" "$project/recovered" --force
  [[ $(survey_kv "$project/recovered" X_SURVEY_GRAPH) == ready ]]
  [[ $(survey_kv "$project/recovered" X_SURVEY_NAV) == graph ]]
  run_graph_survey "$repo" "$XDH" "$bin" "$project/recovered-fresh"
  [[ $(survey_kv "$project/recovered-fresh" X_SURVEY_STATE) == fresh ]] || {
    echo '.codegraph runtime invalidated the survey cache' >&2
    return 1
  }
}

run_test --fast 'survey cache tracks content, first-run ignore, and root scope' \
  test_cache_tracks_content_first_run_and_subdirectory_scope
run_test --fast 'failed graph sync stays degraded and graph runtime is excluded' \
  test_failed_graph_sync_stays_degraded_and_index_is_not_cache_input

skill_x_test_finish 'survey cache regressions'
