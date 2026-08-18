#!/usr/bin/env bash
# Coverage for `xdh survey` and for the two token-cost guards that keep the
# x-* skill set from quietly growing back: the survey's size cap, and a
# per-skill byte budget on what a deployed skill loads into an agent's context.
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(cd -- "$(mktemp -d "${TMPDIR:-/tmp}/skill-x-survey.XXXXXX")" && pwd -P)
trap 'rm -rf "$TEST_ROOT"' EXIT

export SKILL_X_OPENCODE_VERSION=v1

# shellcheck source=lib/harness.sh
source "$PROJECT_ROOT/tests/lib/harness.sh"
skill_x_test_parse_args "$@"

# A throwaway repository with enough shape for every survey section to have
# something to find, plus the deployed xdh a synced tool would actually run.
make_survey_fixture() {
  local project=$1 repo=$2
  copy_built_project "$project"
  mkdir -p "$repo/src" "$repo/tests" "$repo/.github/workflows" "$repo/bin"
  git init -q -b main "$repo"
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name 'Test Runner'

  printf '# Demo\n\nA fixture project.\n' > "$repo/README.md"
  printf '# Architecture\n\nLayers.\n' > "$repo/ARCHITECTURE.md"
  printf 'console.log("hi")\n' > "$repo/src/index.js"
  printf 'export const a = 1\n' > "$repo/src/lib.js"
  printf 'test("x", () => {})\n' > "$repo/tests/lib.test.js"
  printf '#!/bin/sh\necho run\n' > "$repo/bin/run.sh"
  cat > "$repo/package.json" <<'EOF'
{
  "name": "demo",
  "main": "src/index.js",
  "scripts": {
    "build": "node build.js",
    "test": "node --test"
  }
}
EOF
  cat > "$repo/Makefile" <<'EOF'
.PHONY: check
check:
	npm test
lint:
	eslint .
EOF
  cat > "$repo/.github/workflows/ci.yml" <<'EOF'
name: ci
jobs:
  build:
    steps:
      - run: npm ci
      - run: npm test
EOF
  git -C "$repo" add -A
  git -C "$repo" commit -qm initial
}

survey_kv() { sed -n "s/^$2=//p" "$1"; }

test_survey_emits_every_key_within_budget() {
  local project="$TEST_ROOT/keys" repo="$TEST_ROOT/keys-repo"
  make_survey_fixture "$project" "$repo"
  local XDH="$project/commands/x-discovery/scripts/xdh"

  ( cd "$repo" && "$XDH" survey ensure ) > "$project/out"

  local file state head bytes
  file=$(survey_kv "$project/out" X_SURVEY_FILE)
  state=$(survey_kv "$project/out" X_SURVEY_STATE)
  head=$(survey_kv "$project/out" X_SURVEY_HEAD)
  bytes=$(survey_kv "$project/out" X_SURVEY_BYTES)

  [[ -n $file && -f $file ]]
  [[ $state == rebuilt ]]
  [[ $head =~ ^[0-9a-f]{40}$ ]]
  [[ $bytes =~ ^[0-9]+$ ]]

  # The cap is the whole point: an unbounded survey just moves the token cost
  # from walking the tree to reading the survey.
  (( bytes <= 8192 ))
  [[ $(wc -c < "$file" | tr -d ' ') -eq $bytes ]]

  # Every section a consuming skill is told to rely on must be present.
  local s
  for s in '## Repository' '## Layout' '## File types' '## Entry points' \
           '## Docs' '## Tests' '## DevEx commands' '## Change hotspots'; do
    rg -qF "$s" "$file" || { echo "missing section: $s" >&2; return 1; }
  done

  # And the mechanically-derived facts must actually be derived.
  rg -qF 'README.md' "$file"
  rg -qF 'npm run build' "$file"
  rg -qF 'make lint' "$file"
  rg -qF 'src/index.js' "$file"
  # `.PHONY` is a Make directive, not a command a developer runs.
  rg -qF 'make .PHONY' "$file" && { echo 'Make directive leaked as a target' >&2; return 1; }
  return 0
}

test_survey_is_cached_until_the_tree_moves() {
  local project="$TEST_ROOT/cache" repo="$TEST_ROOT/cache-repo"
  make_survey_fixture "$project" "$repo"
  local XDH="$project/commands/x-discovery/scripts/xdh"

  ( cd "$repo" && "$XDH" survey ensure ) > "$project/first"
  [[ $(survey_kv "$project/first" X_SURVEY_STATE) == rebuilt ]]

  # Nothing changed: the second caller pays a read, not a rebuild. This is what
  # lets x-discovery and x-plan-eng both call ensure unconditionally.
  ( cd "$repo" && "$XDH" survey ensure ) > "$project/second"
  [[ $(survey_kv "$project/second" X_SURVEY_STATE) == fresh ]]

  # An uncommitted edit invalidates: the key includes `git status --porcelain`.
  printf 'export const b = 2\n' >> "$repo/src/lib.js"
  ( cd "$repo" && "$XDH" survey ensure ) > "$project/dirty"
  [[ $(survey_kv "$project/dirty" X_SURVEY_STATE) == rebuilt ]]
  ( cd "$repo" && "$XDH" survey ensure ) > "$project/dirty2"
  [[ $(survey_kv "$project/dirty2" X_SURVEY_STATE) == fresh ]]

  # Committing moves HEAD, so it invalidates again even though the working tree
  # is now clean and the porcelain digest returns to its original value.
  git -C "$repo" add -A
  git -C "$repo" commit -qm second
  ( cd "$repo" && "$XDH" survey ensure ) > "$project/committed"
  [[ $(survey_kv "$project/committed" X_SURVEY_STATE) == rebuilt ]]

  # --force rebuilds a valid cache on demand.
  ( cd "$repo" && "$XDH" survey ensure --force ) > "$project/forced"
  [[ $(survey_kv "$project/forced" X_SURVEY_STATE) == rebuilt ]]
}

test_survey_path_reports_without_building() {
  local project="$TEST_ROOT/path" repo="$TEST_ROOT/path-repo"
  make_survey_fixture "$project" "$repo"
  local XDH="$project/commands/x-discovery/scripts/xdh"

  ( cd "$repo" && "$XDH" survey path ) > "$project/absent"
  [[ $(survey_kv "$project/absent" X_SURVEY_STATE) == absent ]]
  [[ $(survey_kv "$project/absent" X_SURVEY_BYTES) == 0 ]]
  [[ ! -f $(survey_kv "$project/absent" X_SURVEY_FILE) ]]

  ( cd "$repo" && "$XDH" survey ensure ) >/dev/null
  ( cd "$repo" && "$XDH" survey path ) > "$project/fresh"
  [[ $(survey_kv "$project/fresh" X_SURVEY_STATE) == fresh ]]

  printf 'more\n' >> "$repo/README.md"
  ( cd "$repo" && "$XDH" survey path ) > "$project/stale"
  [[ $(survey_kv "$project/stale" X_SURVEY_STATE) == stale ]]
}

test_survey_survives_a_symlinked_directory() {
  # commands-src/*/scripts are symlinks to directories. `wc -l` exits non-zero
  # on those, which under `set -euo pipefail` aborted the whole survey.
  local project="$TEST_ROOT/link" repo="$TEST_ROOT/link-repo"
  make_survey_fixture "$project" "$repo"
  local XDH="$project/commands/x-discovery/scripts/xdh"

  mkdir -p "$repo/shared"
  printf 'x\n' > "$repo/shared/file.txt"
  ln -s ../shared "$repo/src/shared"
  git -C "$repo" add -A
  git -C "$repo" commit -qm symlink

  ( cd "$repo" && "$XDH" survey ensure ) > "$project/out"
  [[ $(survey_kv "$project/out" X_SURVEY_STATE) == rebuilt ]]
  [[ -s $(survey_kv "$project/out" X_SURVEY_FILE) ]]
}

test_survey_is_written_under_gitignored_runtime() {
  # ARCHITECTURE decision #13: only .dev-hub/logs is tracked. A survey that
  # landed in Git would put a rebuilt-on-every-commit artifact into history.
  local project="$TEST_ROOT/ignore" repo="$TEST_ROOT/ignore-repo"
  make_survey_fixture "$project" "$repo"
  local XDH="$project/commands/x-discovery/scripts/xdh"

  ( cd "$repo" && "$XDH" init ) >/dev/null
  ( cd "$repo" && "$XDH" survey ensure ) > "$project/out"
  local file
  file=$(survey_kv "$project/out" X_SURVEY_FILE)
  [[ $file == "$repo/.dev-hub/runtime/survey/survey.md" ]]
  git -C "$repo" status --porcelain | rg -q '\.dev-hub/runtime' && {
    echo 'survey is visible to Git' >&2
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# Code graph routing.
#
# Driven by a stub `codegraph` on PATH rather than the real CLI: CI must not
# install an npm package to run the suite, and a stub is the only way to assert
# what the survey *does not* call (no sync on a fresh survey) or to force a
# failing sync deterministically.
# ---------------------------------------------------------------------------

# Write a fake codegraph that logs every invocation and answers `status` with
# the node count it was built with. `nodes=fail-sync` makes `sync` exit non-zero.
make_codegraph_stub() {
  local bindir=$1 nodes=$2
  mkdir -p "$bindir"
  cat > "$bindir/codegraph" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\$CODEGRAPH_STUB_LOG"
case \${1:-} in
  sync)
    [[ "$nodes" == fail-sync ]] && exit 1
    exit 0
    ;;
  status)
    printf '\nIndex Statistics:\n  Files:     10\n  Nodes:     %s\n  Edges:     40\n' "$nodes"
    ;;
esac
exit 0
EOF
  chmod +x "$bindir/codegraph"
}

# A repo whose language mix crosses the supported-share threshold.
make_graph_repo() {
  local repo=$1
  mkdir -p "$repo/src"
  git init -q -b main "$repo"
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name 'Test Runner'
  local i
  for i in 1 2 3 4 5 6 7 8; do printf 'export const v%s = %s\n' "$i" "$i" > "$repo/src/m$i.ts"; done
  printf '# Demo\n' > "$repo/README.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm initial
}

run_graph_survey() {
  local repo=$1 xdh=$2 bindir=$3 out=$4
  ( cd "$repo" && PATH="$bindir:$PATH" CODEGRAPH_STUB_LOG="$bindir/stub.log" "$xdh" survey ensure ) > "$out"
}

test_graph_route_is_taken_only_when_the_index_is_usable() {
  local project="$TEST_ROOT/nav" repo="$TEST_ROOT/nav-repo" bin="$TEST_ROOT/nav-bin"
  copy_built_project "$project"
  make_graph_repo "$repo"
  local XDH="$project/commands/x-discovery/scripts/xdh"

  # 1. No codegraph on PATH at all.
  ( cd "$repo" && env PATH="/usr/bin:/bin" "$XDH" survey ensure ) > "$project/absent" 2>"$project/absent.err"
  [[ $(survey_kv "$project/absent" X_SURVEY_NAV) == files ]]
  [[ $(survey_kv "$project/absent" X_SURVEY_GRAPH) == absent ]]
  # A project without the tool is ordinary, not a problem: no noise on stderr.
  [[ ! -s "$project/absent.err" ]]

  # 2. Installed, but the project has no index yet.
  make_codegraph_stub "$bin" 500
  rm -rf "$repo/.dev-hub"
  run_graph_survey "$repo" "$XDH" "$bin" "$project/uninit"
  [[ $(survey_kv "$project/uninit" X_SURVEY_GRAPH) == uninitialized ]]
  [[ $(survey_kv "$project/uninit" X_SURVEY_NAV) == files ]]

  # 3. Initialized but the index found nothing — the shell-project shape.
  mkdir -p "$repo/.codegraph"
  make_codegraph_stub "$bin" 0
  rm -rf "$repo/.dev-hub"
  run_graph_survey "$repo" "$XDH" "$bin" "$project/empty"
  [[ $(survey_kv "$project/empty" X_SURVEY_GRAPH) == empty ]]
  [[ $(survey_kv "$project/empty" X_SURVEY_NAV) == files ]]

  # 4. A real index: the graph route, and the section that carries the commands.
  make_codegraph_stub "$bin" 1234
  rm -rf "$repo/.dev-hub"
  run_graph_survey "$repo" "$XDH" "$bin" "$project/ready"
  [[ $(survey_kv "$project/ready" X_SURVEY_GRAPH) == ready ]]
  [[ $(survey_kv "$project/ready" X_SURVEY_NAV) == graph ]]
  [[ $(survey_kv "$project/ready" X_SURVEY_GRAPH_SYMBOLS) == 1234 ]]
  local file
  file=$(survey_kv "$project/ready" X_SURVEY_FILE)
  rg -qF '## Code graph' "$file"
  rg -qF 'codegraph impact' "$file"
  # The advice must stay: plain output, not --json.
  rg -qF 'not `--json`' "$file"
  [[ $(survey_kv "$project/ready" X_SURVEY_BYTES) -le 8192 ]]
}

test_graph_route_is_refused_for_a_shell_project() {
  # skill-x's own shape: CodeGraph indexes no shell or Markdown, so a usable
  # binary and even an index directory must still route to files.
  local project="$TEST_ROOT/shell" repo="$TEST_ROOT/shell-repo" bin="$TEST_ROOT/shell-bin"
  copy_built_project "$project"
  mkdir -p "$repo/bin"
  git init -q -b main "$repo"
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name 'Test Runner'
  local i
  for i in 1 2 3 4 5 6; do printf '#!/bin/sh\necho %s\n' "$i" > "$repo/bin/s$i.sh"; done
  printf '# Docs\n' > "$repo/README.md"
  printf '# More\n' > "$repo/ARCHITECTURE.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm initial

  mkdir -p "$repo/.codegraph"
  make_codegraph_stub "$bin" 9999
  local XDH="$project/commands/x-discovery/scripts/xdh"
  run_graph_survey "$repo" "$XDH" "$bin" "$project/out"

  [[ $(survey_kv "$project/out" X_SURVEY_GRAPH) == unsupported ]]
  [[ $(survey_kv "$project/out" X_SURVEY_NAV) == files ]]
  # Classification must short-circuit before spending anything on the tool.
  [[ ! -s "$bin/stub.log" ]]
  rg -qF '## Code graph' "$(survey_kv "$project/out" X_SURVEY_FILE)" && {
    echo 'Code graph section written for an unsupported project' >&2
    return 1
  }
  return 0
}

test_graph_sync_runs_only_when_the_survey_rebuilds() {
  local project="$TEST_ROOT/sync" repo="$TEST_ROOT/sync-repo" bin="$TEST_ROOT/sync-bin"
  copy_built_project "$project"
  make_graph_repo "$repo"
  mkdir -p "$repo/.codegraph"
  make_codegraph_stub "$bin" 777
  local XDH="$project/commands/x-discovery/scripts/xdh"

  run_graph_survey "$repo" "$XDH" "$bin" "$project/first"
  [[ $(survey_kv "$project/first" X_SURVEY_STATE) == rebuilt ]]
  [[ $(rg -c '^sync' "$bin/stub.log" || true) -eq 1 ]]

  # A fresh survey means nothing moved, so the graph cannot have gone stale:
  # the second call must not pay for a sync.
  run_graph_survey "$repo" "$XDH" "$bin" "$project/second"
  [[ $(survey_kv "$project/second" X_SURVEY_STATE) == fresh ]]
  [[ $(survey_kv "$project/second" X_SURVEY_NAV) == graph ]]
  [[ $(rg -c '^sync' "$bin/stub.log" || true) -eq 1 ]]

  # An edit moves the key, so the next call syncs again.
  printf 'export const extra = 1\n' >> "$repo/src/m1.ts"
  run_graph_survey "$repo" "$XDH" "$bin" "$project/third"
  [[ $(survey_kv "$project/third" X_SURVEY_STATE) == rebuilt ]]
  [[ $(rg -c '^sync' "$bin/stub.log" || true) -eq 2 ]]

  # `survey path` reports only; it must never sync.
  ( cd "$repo" && PATH="$bin:$PATH" CODEGRAPH_STUB_LOG="$bin/stub.log" "$XDH" survey path ) >/dev/null
  [[ $(rg -c '^sync' "$bin/stub.log" || true) -eq 2 ]]
}

test_graph_degrades_when_sync_fails() {
  # A graph that could not be brought up to date is worse than no graph: it
  # answers confidently from stale edges. The survey must still be produced.
  local project="$TEST_ROOT/stale" repo="$TEST_ROOT/stale-repo" bin="$TEST_ROOT/stale-bin"
  copy_built_project "$project"
  make_graph_repo "$repo"
  mkdir -p "$repo/.codegraph"
  make_codegraph_stub "$bin" fail-sync
  local XDH="$project/commands/x-discovery/scripts/xdh"

  run_graph_survey "$repo" "$XDH" "$bin" "$project/out"
  [[ $(survey_kv "$project/out" X_SURVEY_GRAPH) == stale ]]
  [[ $(survey_kv "$project/out" X_SURVEY_NAV) == files ]]
  [[ -s $(survey_kv "$project/out" X_SURVEY_FILE) ]]
  [[ $(survey_kv "$project/out" X_SURVEY_STATE) == rebuilt ]]
}

test_graph_reports_the_test_glob_affected_actually_needs() {
  # `codegraph affected` defaults to *.test.* / *.spec.* only. On a Python suite
  # named test_*.py it answers "No test files affected" — which reads exactly
  # like a real empty result. Deriving the glob here is what prevents that.
  local project="$TEST_ROOT/glob" bin="$TEST_ROOT/glob-bin"
  copy_built_project "$project"
  make_codegraph_stub "$bin" 321
  local XDH="$project/commands/x-discovery/scripts/xdh"

  local spec name pattern want repo
  for spec in 'py:src/mod%s.py:tests/test_mod%s.py:**/test_*.py' \
              'go:src/mod%s.go:src/mod%s_test.go:**/*_test.go' \
              'ts:src/mod%s.ts:src/mod%s.spec.ts:**/*.{test,spec}.{ts,tsx,js,jsx}'; do
    name=${spec%%:*}
    repo="$TEST_ROOT/glob-$name"
    local rest=${spec#*:} srcpat testpat
    srcpat=${rest%%:*}; rest=${rest#*:}
    testpat=${rest%%:*}; want=${rest#*:}

    mkdir -p "$repo/src" "$repo/tests"
    git init -q -b main "$repo"
    git -C "$repo" config user.email test@example.invalid
    git -C "$repo" config user.name 'Test Runner'
    local i f
    for i in 1 2 3 4 5 6; do
      # shellcheck disable=SC2059
      f=$(printf "$srcpat" "$i"); mkdir -p "$(dirname "$repo/$f")"; printf 'x\n' > "$repo/$f"
      # shellcheck disable=SC2059
      f=$(printf "$testpat" "$i"); mkdir -p "$(dirname "$repo/$f")"; printf 'x\n' > "$repo/$f"
    done
    git -C "$repo" add -A
    git -C "$repo" commit -qm initial
    mkdir -p "$repo/.codegraph"

    run_graph_survey "$repo" "$XDH" "$bin" "$project/$name.out"
    [[ $(survey_kv "$project/$name.out" X_SURVEY_NAV) == graph ]] ||
      { echo "$name: expected the graph route" >&2; return 1; }
    rg -qF "$want" "$(survey_kv "$project/$name.out" X_SURVEY_FILE)" ||
      { echo "$name: survey did not report the glob $want" >&2; return 1; }
  done
}

# ---------------------------------------------------------------------------
# Token budgets.
#
# A skill's SKILL.md is loaded in full whenever the skill runs, so its size is a
# recurring per-invocation cost, not a one-off. Every budget below is a ceiling
# on the *deployed* artifact (header injected, provenance stripped). Raising one
# is allowed; doing it without noticing is what these numbers prevent.
# ---------------------------------------------------------------------------

test_deployed_skills_stay_within_budget() {
  local project="$TEST_ROOT/budget"
  copy_built_project "$project"

  local spec name limit actual
  # Kept a little above current size so ordinary wording edits do not trip it.
  # x-plan-eng's ceiling was raised from 15000 when CodeGraph routing landed: it
  # gained the route switch, the mechanical sources for three IS sections, and
  # the warning about `affected` returning empty silently. Ceilings move for a
  # stated reason, never by drift.
  for spec in \
    'x-discovery:9000' \
    'x-plan:15000' \
    'x-plan-eng:16000' \
    'x-plan-product:5000' \
    'x-plan-design:5500' \
    'x-plan-devex:4500' \
    'codegraph:6500' \
  ; do
    name=${spec%%:*}
    limit=${spec##*:}
    actual=$(wc -c < "$project/commands/$name/SKILL.md" | tr -d ' ')
    if (( actual > limit )); then
      echo "$name/SKILL.md is $actual bytes, over its $limit budget" >&2
      return 1
    fi
  done
}

test_provenance_is_stripped_from_deployed_skills() {
  local project="$TEST_ROOT/prov"
  copy_built_project "$project"

  # Provenance is maintenance history for the repository, never instruction for
  # the agent, so it must exist in source and be absent from the artifact.
  rg -q '^## Provenance' "$project/commands-src/x-plan/SKILL.md"
  if rg -l '^## Provenance' "$project/commands"/*/SKILL.md >"$project/hits" 2>/dev/null; then
    cat "$project/hits" >&2
    echo 'provenance leaked into the deployed artifacts' >&2
    return 1
  fi

  # Stripping must not eat the section that follows it, nor the shared header.
  rg -q '此區塊由 bin/build.sh' "$project/commands/x-plan/SKILL.md"
  rg -q '^## Continuing' "$project/commands/x-plan/SKILL.md"
}

test_orchestrator_does_not_bundle_the_facet_contracts() {
  local project="$TEST_ROOT/contracts"
  copy_built_project "$project"

  # x-plan reads a dispatch table; the full contracts belong to the specialists
  # that run them. Bundling both put the same content in context twice.
  [[ -f "$project/commands/x-plan/references/facet-dispatch.md" ]]
  local leaked
  leaked=$(find "$project/commands/x-plan/references" -name '*facet-contract*' | wc -l | tr -d ' ')
  [[ $leaked -eq 0 ]]

  # Each specialist still carries its own contract: they are self-contained
  # because each is symlinked into the tool's skills directory separately.
  local s
  for s in product design devex eng; do
    [[ -f "$project/commands/x-plan-$s/references/facet-contract.md" ]]
  done
}

run_test --fast 'survey emits every key within budget' test_survey_emits_every_key_within_budget
run_test --fast 'survey is cached until the tree moves' test_survey_is_cached_until_the_tree_moves
run_test 'survey path reports without building' test_survey_path_reports_without_building
run_test 'survey survives a symlinked directory' test_survey_survives_a_symlinked_directory
run_test 'survey stays out of Git' test_survey_is_written_under_gitignored_runtime
run_test --fast 'graph route only when the index is usable' test_graph_route_is_taken_only_when_the_index_is_usable
run_test --fast 'graph route refused for a shell project' test_graph_route_is_refused_for_a_shell_project
run_test 'graph sync runs only when the survey rebuilds' test_graph_sync_runs_only_when_the_survey_rebuilds
run_test 'graph degrades when sync fails' test_graph_degrades_when_sync_fails
run_test 'graph reports the test glob affected needs' test_graph_reports_the_test_glob_affected_actually_needs
run_test --fast 'deployed skills stay within budget' test_deployed_skills_stay_within_budget
run_test --fast 'provenance is stripped from artifacts' test_provenance_is_stripped_from_deployed_skills
run_test --fast 'orchestrator does not bundle facet contracts' test_orchestrator_does_not_bundle_the_facet_contracts

skill_x_test_finish 'survey and token budgets'
