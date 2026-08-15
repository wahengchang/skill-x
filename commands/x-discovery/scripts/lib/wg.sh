# shellcheck shell=bash
# Work Group plumbing: 1 WG = 1 branch = 1 worktree = 1 PR.

# Create (or adopt) the branch, worktree and WG document for one delivery unit.
# Every step is idempotent: re-running never produces WG-002 for work that is
# already WG-001, never creates a second branch, and never re-adds a worktree.
x_wg_new() {
  local slug="" title="" cycle="" items="—" owner="—" base="" from=""
  while (( $# )); do
    case $1 in
      --slug) slug=$2; shift 2 ;;
      --title) title=$2; shift 2 ;;
      --cycle) cycle=$2; shift 2 ;;
      --items) items=$2; shift 2 ;;
      --owner) owner=$2; shift 2 ;;
      --base) base=$2; shift 2 ;;
      --from) from=$2; shift 2 ;;
      *) x_die "wg new: unknown option $1" ;;
    esac
  done
  x_require_value --slug "$slug"
  slug=$(x_slugify "$slug")
  [[ -n $slug ]] || x_die "--slug must contain at least one alphanumeric character"

  x_ensure_dev_hub
  x_ensure_gitignore >/dev/null
  [[ -n $base ]] || base=$(x_base_branch)
  [[ -n $from ]] || from=$(x_base_ref "$base")

  local cycle_dir="" stamp target_dir
  if cycle_dir=$(x_cycle_resolve "$cycle" 2>/dev/null); then
    stamp=$(x_cycle_stamp "$(basename -- "$cycle_dir")")
    target_dir="$cycle_dir/work-groups"
  else
    # Standalone mode: no Cycle required, the WG document lives in runtime.
    cycle_dir=$(x_runtime_new --skill x-plan-eng --slug "$slug" | sed -n 's/^X_RUNTIME_DIR=//p')
    stamp=$(x_stamp)
    target_dir=$cycle_dir
  fi
  mkdir -p "$target_dir"

  # Reservation is one critical section: the "does a WG for this slug already
  # exist?" scan, the number allocation, and the write that makes the number
  # visible to the next scan all happen under the same lock. Splitting them
  # lets two agents planning at the same moment both observe an empty
  # work-groups/ and both claim WG-001.
  local id file existing found=no lower branch worktree
  x_lock "$cycle_dir/.xdh-id.lock"
  for existing in "$target_dir/WG-"*"-$slug.md"; do
    if [[ -f $existing ]]; then
      id=$(basename -- "$existing" | cut -d- -f1,2)
      file=$existing
      found=yes
      break
    fi
  done

  if [[ $found == yes ]]; then
    # An existing WG owns its branch and worktree names; never recompute them,
    # because a recomputed stamp can differ from the one already recorded.
    branch=$(x_field_get "$file" Branch | tr -d '`')
    worktree=$(x_field_get "$file" Worktree | tr -d '`')
  else
    id=$(x_id_next WG "$cycle_dir")
    file="$target_dir/$id-$slug.md"
    lower=$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')
    branch="x/$stamp-$lower-$slug"
    worktree="$X_WORKTREES/$stamp-$id-$slug"
    x_render_template "$(x_template work-group)" \
      ID "$id" \
      TITLE "${title:-$slug}" \
      OWNER "$owner" \
      ITEMS "$items" \
      BRANCH "$branch" \
      WORKTREE "$worktree" \
      BASE "$base" \
      CREATED "$(x_now_iso)" \
      | x_atomic_write "$file"
  fi
  x_unlock

  # The worktree is created outside the lock: it is slow, and it is derived
  # from the reservation rather than part of it. A failure here leaves the
  # reservation intact, so re-running finishes the job instead of renumbering.
  x_worktree_ensure "$branch" "$worktree" "$from"

  x_emit X_WG_ID "$id"
  x_emit X_WG_FILE "$file"
  x_emit X_WG_BRANCH "$branch"
  x_emit X_WG_WORKTREE "$worktree"
  x_emit X_WG_BASE "$base"
  x_emit X_WG_REUSED "$found"
}

x_worktree_registered() {
  git -C "$X_MAIN_ROOT" worktree list --porcelain | grep -Fxq "worktree $1"
}

x_worktree_ensure() {
  local branch=$1 path=$2 from=$3
  x_resolve_paths

  if x_worktree_registered "$path"; then
    # Registration alone is not proof that the worktree is usable: the
    # directory may have been deleted by hand, leaving metadata that keeps
    # `worktree add` failing while every re-run happily reports "reused".
    if [[ -e $path/.git ]]; then
      local actual
      actual=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
      [[ $actual == "$branch" ]] ||
        x_die "worktree $path is on branch '${actual:-unknown}', expected '$branch'"
      x_emit X_WORKTREE_CREATED no
      return 0
    fi
    git -C "$X_MAIN_ROOT" worktree prune >/dev/null 2>&1 || true
    if x_worktree_registered "$path"; then
      x_die "stale worktree registration for $path could not be pruned"
    fi
    x_emit X_WORKTREE_PRUNED yes
  fi

  if [[ -e $path ]]; then
    x_die "worktree path already occupied by untracked content: $path"
  fi

  mkdir -p "$(dirname -- "$path")"
  if git -C "$X_MAIN_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$X_MAIN_ROOT" worktree add "$path" "$branch" >/dev/null
  else
    git -C "$X_MAIN_ROOT" worktree add -b "$branch" "$path" "$from" >/dev/null
  fi
  x_emit X_WORKTREE_CREATED yes
}

x_worktree_list() {
  x_resolve_paths
  local path="" branch=""
  while IFS= read -r line; do
    case $line in
      "worktree "*) path=${line#worktree }; branch="" ;;
      "branch "*) branch=${line#branch refs/heads/} ;;
      "detached") branch="(detached)" ;;
      "")
        [[ -n $path ]] && printf 'WORKTREE %s %s\n' "${branch:-(none)}" "$path"
        path=""
        ;;
    esac
  done < <(git -C "$X_MAIN_ROOT" worktree list --porcelain; printf '\n')
}

x_worktree_remove() {
  local path="" force=no
  while (( $# )); do
    case $1 in
      --path) path=$2; shift 2 ;;
      --force) force=yes; shift ;;
      *) x_die "worktree remove: unknown option $1" ;;
    esac
  done
  x_require_value --path "$path"
  x_resolve_paths

  # Never destroy uncommitted work, even when asked to force.
  if [[ -d $path ]] && [[ -n $(git -C "$path" status --porcelain 2>/dev/null) ]]; then
    x_die "refusing to remove a dirty worktree: $path"
  fi
  if [[ $force == yes ]]; then
    git -C "$X_MAIN_ROOT" worktree remove --force "$path" >/dev/null
  else
    git -C "$X_MAIN_ROOT" worktree remove "$path" >/dev/null
  fi
  x_emit X_WORKTREE_REMOVED "$path"
}
