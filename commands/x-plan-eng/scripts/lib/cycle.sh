# shellcheck shell=bash
# Cycle lifecycle: create, resolve, allocate IDs, materialise work items, close.

# Terminal states differ by document kind: a work item is finished when it is
# done/cancelled/deferred, a Work Group when its delivery landed or was closed.
# Both the Cycle closure gate and the housekeeping sweep ask this one question,
# so the two lists live here rather than being restated at each call site.
X_TERMINAL_STATUSES="done cancelled deferred"
X_TERMINAL_WG_STATUSES="merged closed cancelled done"

x_status_is_terminal() {
  local kind=$1 status
  status=$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')
  [[ -n $status ]] || return 1
  case $kind in
    WG) [[ " $X_TERMINAL_WG_STATUSES " == *" $status "* ]] ;;
    *) [[ " $X_TERMINAL_STATUSES " == *" $status "* ]] ;;
  esac
}

x_cycle_dir_for_slug() {
  local slug=$1 dir
  x_resolve_paths
  for dir in "$X_ACTIVE"/cycle-*-"$slug"; do
    [[ -d $dir ]] || continue
    printf '%s' "$dir"
    return 0
  done
  return 1
}

x_cycle_list() {
  x_resolve_paths
  local dir found=0
  for dir in "$X_ACTIVE"/cycle-*; do
    [[ -d $dir ]] || continue
    found=1
    printf 'CYCLE %s %s\n' "$(basename -- "$dir")" "$dir"
  done
  (( found )) || return 1
}

# Resolve exactly one Cycle. An explicit name always wins; otherwise a single
# active Cycle is used and ambiguity is reported rather than guessed.
x_cycle_resolve() {
  local want=${1:-}
  x_resolve_paths
  if [[ -n $want ]]; then
    local dir="$X_ACTIVE/$want"
    [[ -d $dir ]] || dir=$(x_cycle_dir_for_slug "$want") || x_die "no such cycle: $want"
    printf '%s' "$dir"
    return 0
  fi
  local dirs=() dir
  for dir in "$X_ACTIVE"/cycle-*; do
    if [[ -d $dir ]]; then dirs+=("$dir"); fi
  done
  case ${#dirs[@]} in
    0) x_die "no active cycle; run 'xdh cycle new --slug <slug>' or pass --cycle" ;;
    1) printf '%s' "${dirs[0]}" ;;
    *) x_die "multiple active cycles; pass --cycle <name>" ;;
  esac
}

# Where planning documents live when there is no Cycle. The path is fixed, not
# timestamped: a scope that moves every invocation can never be scanned for
# reuse, and a lock taken inside it protects nothing, so standalone planning
# would silently lose both idempotency and mutual exclusion.
x_standalone_dir() {
  x_ensure_dev_hub
  x_ensure_gitignore >/dev/null
  local dir="$X_RUNTIME/standalone"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# Single scope-resolution rule for every document-creating command.
# --dir wins; then a named Cycle; then the only active Cycle; then standalone.
# Several active Cycles stay an error — a fallback must never turn ambiguity
# into a silent guess.
x_scope_dir_for() {
  local cycle=${1:-} dir=${2:-}
  if [[ -n $dir ]]; then
    printf '%s' "$dir"
    return 0
  fi
  if [[ -n $cycle ]]; then
    x_cycle_resolve "$cycle"
    return 0
  fi
  x_resolve_paths
  local dirs=() d
  for d in "$X_ACTIVE"/cycle-*; do
    if [[ -d $d ]]; then dirs+=("$d"); fi
  done
  case ${#dirs[@]} in
    0) x_standalone_dir ;;
    1) printf '%s' "${dirs[0]}" ;;
    *) x_die "multiple active cycles; pass --cycle <name>" ;;
  esac
}

# True when the resolved scope is the standalone directory rather than a Cycle,
# which decides whether documents go into work-items/ and work-groups/
# subdirectories or sit directly in the scope.
x_scope_is_cycle() {
  x_resolve_paths
  [[ $1 == "$X_ACTIVE"/* ]]
}

x_cycle_stamp() {
  # cycle-YYYYMMDD-HHmm-slug -> YYYYMMDD-HHmm
  local name=$1
  name=${name#cycle-}
  printf '%s' "${name%%-*}-$(printf '%s' "${name#*-}" | cut -d- -f1)"
}

x_cycle_new() {
  local slug="" title="" scope="" prompt=""
  while (( $# )); do
    case $1 in
      --slug) slug=$2; shift 2 ;;
      --title) title=$2; shift 2 ;;
      --scope) scope=$2; shift 2 ;;
      --prompt) prompt=$2; shift 2 ;;
      *) x_die "cycle new: unknown option $1" ;;
    esac
  done
  x_require_value --slug "$slug"
  slug=$(x_slugify "$slug")
  [[ -n $slug ]] || x_die "--slug must contain at least one alphanumeric character"
  x_ensure_dev_hub
  x_ensure_gitignore >/dev/null

  # Re-running discovery over the same scope updates the existing Cycle instead
  # of forking a second one. Lookup and creation are locked together: the
  # directory name carries a minute-resolution stamp, so two unsynchronised
  # runs that straddle a minute boundary would otherwise create two active
  # Cycles for one scope and make every later lookup ambiguous.
  local dir reused=yes
  x_lock "$X_DEV_HUB/.xdh-cycle.lock"
  if ! dir=$(x_cycle_dir_for_slug "$slug"); then
    reused=no
    dir="$X_ACTIVE/cycle-$(x_stamp)-$slug"
  fi
  mkdir -p "$dir/work-items" "$dir/work-groups" \
           "$dir/artifacts/discovery" "$dir/artifacts/reviews" "$dir/artifacts/debug" \
           "$dir/tmp"

  local name; name=$(basename -- "$dir")
  if [[ ! -f $dir/hub.md ]]; then
    x_render_template "$(x_template cycle-hub)" \
      TITLE "${title:-$slug}" \
      CYCLE "$name" \
      CREATED "$(x_now_iso)" \
      SCOPE "${scope:-<what was inspected>}" \
      SOURCE_PROMPT "${prompt:-<summary or reference>}" \
      | x_atomic_write "$dir/hub.md"
  fi
  x_unlock

  x_emit X_CYCLE "$name"
  x_emit X_CYCLE_DIR "$dir"
  x_emit X_CYCLE_HUB "$dir/hub.md"
  x_emit X_CYCLE_REUSED "$reused"
}

x_cycle_show() {
  local dir=$1 name
  name=$(basename -- "$dir")
  x_emit X_CYCLE "$name"
  x_emit X_CYCLE_DIR "$dir"
  x_emit X_CYCLE_HUB "$dir/hub.md"
  x_emit X_CYCLE_STAMP "$(x_cycle_stamp "$name")"
}

# Highest existing number for a prefix across filenames and the hub table, +1.
# Both sources are scanned because WK candidates only ever live in hub.md while
# IS/SP/WG/RV/DBG live in files, and an ID must never be reused across either.
x_id_next() {
  local kind=$1 dir=$2 max=0 n
  local found
  found=$( { find "$dir" -type f -name "$kind-*" -exec basename {} \; 2>/dev/null || true
             grep -rhoE "(^|[^A-Za-z0-9])$kind-[0-9]+" "$dir" 2>/dev/null || true; } |
           grep -oE "$kind-[0-9]+" | sed "s/^$kind-//" || true)
  for n in $found; do
    n=$((10#$n))
    if (( n > max )); then max=$n; fi
  done
  printf '%s-%03d' "$kind" "$((max + 1))"
}

x_item_new() {
  local type="" slug="" title="" cycle="" source="—" owner="—" wg="—" priority="P2" dir=""
  while (( $# )); do
    case $1 in
      --type) type=$2; shift 2 ;;
      --slug) slug=$2; shift 2 ;;
      --title) title=$2; shift 2 ;;
      --cycle) cycle=$2; shift 2 ;;
      --dir) dir=$2; shift 2 ;;
      --source) source=$2; shift 2 ;;
      --owner) owner=$2; shift 2 ;;
      --wg) wg=$2; shift 2 ;;
      --priority) priority=$2; shift 2 ;;
      *) x_die "item new: unknown option $1" ;;
    esac
  done
  x_require_value --type "$type"
  x_require_value --slug "$slug"
  slug=$(x_slugify "$slug")
  [[ -n $slug ]] || x_die "--slug must contain at least one alphanumeric character"

  local kind template
  case $type in
    issue) kind=IS; template=$(x_template issue) ;;
    spike) kind=SP; template=$(x_template spike) ;;
    *) x_die "item new: --type must be issue or spike" ;;
  esac

  local scope_dir target_dir
  scope_dir=$(x_scope_dir_for "$cycle" "$dir")
  if [[ -z $dir ]] && x_scope_is_cycle "$scope_dir"; then
    target_dir="$scope_dir/work-items"
  else
    target_dir=$scope_dir
  fi
  mkdir -p "$target_dir"

  # Re-running planning for the same work must not create IS-002 next to an
  # identical IS-001. The reuse scan, the allocation, and the write share one
  # critical section — scanning outside the lock lets two concurrent agents
  # both conclude "nothing exists yet" and then create two items for one job.
  local existing id file reused=no
  x_lock "$scope_dir/.xdh-id.lock"
  for existing in "$target_dir/$kind-"*"-$slug.md"; do
    if [[ -f $existing ]]; then
      id=$(basename -- "$existing" | cut -d- -f1,2)
      file=$existing
      reused=yes
      break
    fi
  done
  if [[ $reused == no ]]; then
    id=$(x_id_next "$kind" "$scope_dir")
    file="$target_dir/$id-$slug.md"
    x_render_template "$template" \
      ID "$id" \
      TITLE "${title:-$slug}" \
      PRIORITY "$priority" \
      OWNER "$owner" \
      WG "$wg" \
      SOURCE "$source" \
      CREATED "$(x_now_iso)" \
      | x_atomic_write "$file"
  fi
  x_unlock

  x_emit X_ITEM_ID "$id"
  x_emit X_ITEM_FILE "$file"
  x_emit X_ITEM_REUSED "$reused"
}

# Allocate an artifact ID and file (RV under artifacts/reviews, DBG under
# artifacts/debug, or anywhere with --dir for standalone runs).
x_artifact_new() {
  local kind="" cycle="" dir="" target="—" base="—" implementer="—" reviewer="—"
  local independent="unknown" fingerprint="—" tree="—"
  while (( $# )); do
    case $1 in
      --kind) kind=$2; shift 2 ;;
      --cycle) cycle=$2; shift 2 ;;
      --dir) dir=$2; shift 2 ;;
      --target) target=$2; shift 2 ;;
      --base) base=$2; shift 2 ;;
      --implementer) implementer=$2; shift 2 ;;
      --reviewer) reviewer=$2; shift 2 ;;
      --independent) independent=$2; shift 2 ;;
      --fingerprint) fingerprint=$2; shift 2 ;;
      --tree) tree=$2; shift 2 ;;
      *) x_die "artifact new: unknown option $1" ;;
    esac
  done
  x_require_value --kind "$kind"

  local template subdir
  case $kind in
    RV) template=$(x_template review-result); subdir=artifacts/reviews ;;
    DBG) template=$(x_template debug-report); subdir=artifacts/debug ;;
    *) x_die "artifact new: --kind must be RV or DBG" ;;
  esac

  local scope_dir target_dir
  scope_dir=$(x_scope_dir_for "$cycle" "$dir")
  if [[ -z $dir ]] && x_scope_is_cycle "$scope_dir"; then
    target_dir="$scope_dir/$subdir"
  else
    target_dir=$scope_dir
  fi
  mkdir -p "$target_dir"

  x_lock "$scope_dir/.xdh-id.lock"
  local id; id=$(x_id_next "$kind" "$scope_dir")
  local file="$target_dir/$id.md"
  if [[ $kind == RV ]]; then
    x_render_template "$template" \
      ID "$id" TARGET "$target" BASE "$base" \
      IMPLEMENTER "$implementer" REVIEWER "$reviewer" INDEPENDENT "$independent" \
      FINGERPRINT "$fingerprint" TREE "$tree" CREATED "$(x_now_iso)" \
      | x_atomic_write "$file"
  else
    x_render_template "$template" \
      ID "$id" TARGET "$target" CREATED "$(x_now_iso)" \
      | x_atomic_write "$file"
  fi
  x_unlock

  x_emit X_ARTIFACT_ID "$id"
  x_emit X_ARTIFACT_FILE "$file"
}

x_runtime_new() {
  local skill="" slug=""
  while (( $# )); do
    case $1 in
      --skill) skill=$2; shift 2 ;;
      --slug) slug=$2; shift 2 ;;
      *) x_die "runtime new: unknown option $1" ;;
    esac
  done
  x_require_value --skill "$skill"
  x_ensure_dev_hub
  x_ensure_gitignore >/dev/null
  skill=$(x_slugify "$skill")
  slug=$(x_slugify "${slug:-run}")
  local dir="$X_RUNTIME/$skill-$(x_stamp_seconds)-${slug:-run}"
  mkdir -p "$dir"
  x_emit X_RUNTIME_DIR "$dir"
}

# Closure gate: every work item terminal, every WG merged or closed, no
# worktree left behind. Prints the blockers instead of a bare refusal.
x_cycle_check() {
  local dir=$1 blockers=0 file status
  for file in "$dir"/work-items/*.md; do
    [[ -f $file ]] || continue
    status=$(x_field_get "$file" Status)
    if ! x_status_is_terminal item "$status"; then
      printf 'BLOCKER work-item %s status=%s\n' "$(basename -- "$file")" "${status:-unknown}"
      blockers=$(( blockers + 1 ))
    fi
  done
  for file in "$dir"/work-groups/*.md; do
    [[ -f $file ]] || continue
    status=$(x_field_get "$file" Status)
    if ! x_status_is_terminal WG "$status"; then
      printf 'BLOCKER work-group %s status=%s\n' "$(basename -- "$file")" "${status:-unknown}"
      blockers=$(( blockers + 1 ))
    fi
    local wt
    wt=$(x_field_get "$file" Worktree | tr -d '`')
    if [[ -n $wt && -d $wt ]]; then
      printf 'BLOCKER worktree %s still present\n' "$wt"
      blockers=$(( blockers + 1 ))
    fi
  done
  x_emit X_CYCLE_BLOCKERS "$blockers"
  (( blockers == 0 ))
}

x_cycle_close() {
  local cycle="" summary="" status="completed" decisions="—" commits="—" force=no
  while (( $# )); do
    case $1 in
      --cycle) cycle=$2; shift 2 ;;
      --summary) summary=$2; shift 2 ;;
      --status) status=$2; shift 2 ;;
      --decisions) decisions=$2; shift 2 ;;
      --commits) commits=$2; shift 2 ;;
      --force) force=yes; shift ;;
      *) x_die "cycle close: unknown option $1" ;;
    esac
  done
  local dir; dir=$(x_cycle_resolve "$cycle")
  local name; name=$(basename -- "$dir")
  x_require_value --summary "$summary"

  if ! x_cycle_check "$dir" && [[ $force != yes ]]; then
    x_die "cycle $name is not closeable; resolve the blockers above"
  fi

  local items groups prs branches
  items=$(find "$dir/work-items" -maxdepth 1 -name '*.md' -exec basename {} .md \; 2>/dev/null |
          sort | x_join || true)
  groups=$(find "$dir/work-groups" -maxdepth 1 -name '*.md' -exec basename {} .md \; 2>/dev/null |
           sort | x_join || true)
  prs=$(for f in "$dir"/work-groups/*.md; do
          if [[ -f $f ]]; then x_field_get "$f" PR; fi
        done | grep -vE '^(—|-)?$' | x_join || true)
  branches=$(for f in "$dir"/work-groups/*.md; do
               if [[ -f $f ]]; then x_field_get "$f" Branch; fi
             done | tr -d '`' | grep -vE '^(—|-)?$' | x_join || true)

  local opened
  opened=$(x_field_get "$dir/hub.md" Created 2>/dev/null || true)

  x_resolve_paths
  mkdir -p "$X_LOGS"
  local log="$X_LOGS/$name.md"
  x_render_template "$(x_template cycle-log)" \
    CYCLE "$name" \
    SUMMARY "$summary" \
    OPENED "${opened:-unknown}" \
    CLOSED "$(x_now_iso)" \
    FINAL_STATUS "$status" \
    ITEMS "${items:-none}" \
    GROUPS "${groups:-none}" \
    BRANCHES "${branches:-none}" \
    PRS "${prs:-none}" \
    COMMITS "$commits" \
    DECISIONS "$decisions" \
    | x_atomic_write "$log"

  rm -rf -- "$dir"
  x_emit X_CYCLE_LOG "$log"
  x_emit X_CYCLE_CLOSED "$name"
}
