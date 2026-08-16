# shellcheck shell=bash
# Work Group plumbing: 1 WG = 1 branch = 1 worktree = 1 PR.

# Normalize an `--items` value: split on commas and whitespace, trim, drop
# empties and the placeholder, de-duplicate, sort (LC_ALL=C), join with commas.
# `—` or empty stays `—`.
x_wg_normalize_items() {
  local raw=$1 out
  out=$(printf '%s' "$raw" | tr ',' '\n' | tr ' ' '\n' |
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
    grep -vE '^(—|-)?$' | LC_ALL=C sort -u | paste -sd, -)
  [[ -n $out ]] || out="—"
  printf '%s' "$out"
}

# Merge two Work-items values into one sorted, de-duplicated list.
x_wg_merge_items() {
  local existing=$1 new=$2 combined
  if [[ $existing == "—" || -z $existing ]]; then combined=$new; else combined="$existing,$new"; fi
  x_wg_normalize_items "$combined"
}

# Reject a `--items` value that names the same ID more than once. Duplicates in
# the input are a caller error and must fail before any WG/branch/worktree side
# effect, never be silently de-duplicated.
x_wg_reject_duplicate_items() {
  local raw=$1 token seen=""
  for token in $(printf '%s' "$raw" | tr ',' ' '); do
    [[ -n $token ]] || continue
    [[ $token == "—" || $token == "-" ]] && continue
    if [[ " $seen " == *" $token "* ]]; then
      x_die "wg new: duplicate item id '$token'"
    fi
    seen="$seen $token"
  done
}

# Resolve an item ID to a unique file within the resolved scope. Returns 0 and
# prints the path, 1 when not found, 2 when ambiguous.
x_wg_resolve_item() {
  local scope_dir=$1 id=$2 target_dir f matches=0 result=""
  if x_scope_is_cycle "$scope_dir"; then
    target_dir="$scope_dir/work-items"
  else
    target_dir=$scope_dir
  fi
  for f in "$target_dir/$id-"*.md; do
    [[ -f $f ]] || continue
    result=$f
    matches=$(( matches + 1 ))
  done
  if (( matches == 1 )); then printf '%s' "$result"; return 0; fi
  (( matches > 1 )) && return 2
  return 1
}

# Create (or adopt) the branch, worktree and WG document for one delivery unit.
# Every step is idempotent: re-running never produces WG-002 for work that is
# already WG-001, never creates a second branch, and never re-adds a worktree.
x_wg_new() {
  local slug="" title="" cycle="" items="—" owner="—" base="" from="" dir=""
  while (( $# )); do
    case $1 in
      --slug) slug=$2; shift 2 ;;
      --title) title=$2; shift 2 ;;
      --cycle) cycle=$2; shift 2 ;;
      --dir) dir=$2; shift 2 ;;
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

  x_wg_reject_duplicate_items "$items"
  items=$(x_wg_normalize_items "$items")

  x_ensure_dev_hub
  x_ensure_gitignore >/dev/null
  [[ -n $base ]] || base=$(x_base_branch)
  [[ -n $from ]] || from=$(x_base_ref "$base")

  # Standalone mode needs no Cycle, but it does need a *stable* scope: the
  # reuse scan, the ID space and the lock all key off this directory.
  local scope_dir stamp target_dir
  scope_dir=$(x_scope_dir_for "$cycle" "$dir")
  if [[ -z $dir ]] && x_scope_is_cycle "$scope_dir"; then
    stamp=$(x_cycle_stamp "$(basename -- "$scope_dir")")
    target_dir="$scope_dir/work-groups"
  else
    stamp=$(x_stamp)
    target_dir=$scope_dir
  fi

  # Strict preflight (before any WG/branch/worktree side effect): validate and
  # resolve every named item to a unique file in the resolved scope. Malformed,
  # missing, or ambiguous items fail the whole command. IFS is left untouched:
  # changing it leaks into x_id_next below, where `for n in $found` relies on
  # default whitespace splitting.
  local -a item_files=()
  local iid ifile
  if [[ $items != "—" ]]; then
    for iid in ${items//,/ }; do
      iid=${iid#"${iid%%[![:space:]]*}"}
      iid=${iid%"${iid##*[![:space:]]}"}
      [[ -n $iid ]] || continue
      [[ $iid =~ ^(WK|IS|SP)-[0-9]{3}$ ]] || x_die "wg new: malformed item id '$iid'"
      ifile=$(x_wg_resolve_item "$scope_dir" "$iid") || x_die "wg new: cannot resolve item '$iid' (missing or ambiguous)"
      item_files+=("$ifile")
    done
  fi

  mkdir -p "$target_dir"

  # Reservation is one critical section: the "does a WG for this slug already
  # exist?" scan, the number allocation, and the write that makes the number
  # visible to the next scan all happen under the same lock. Splitting them
  # lets two agents planning at the same moment both observe an empty
  # work-groups/ and both claim WG-001.
  local id file existing found=no lower branch worktree
  x_lock "$scope_dir/.xdh-id.lock"
  for existing in "$target_dir/WG-"*"-$slug.md"; do
    if [[ -f $existing ]]; then
      id=$(basename -- "$existing" | cut -d- -f1,2)
      file=$existing
      found=yes
      break
    fi
  done

  # Claim items while the WG reservation lock is held. The WG document is the
  # durable claim record, so a concurrent different slug cannot pass before
  # delayed worktree creation writes the cached item header.
  local iwg claim_file claim_items claim_id
  if (( ${#item_files[@]} > 0 )); then
    for ifile in "${item_files[@]}"; do
      iwg=$(x_field_get "$ifile" WG 2>/dev/null || printf '')
      if [[ -n $iwg && $iwg != — && $iwg != - && $iwg != "$id" ]]; then
        x_unlock
        x_die "wg new: item $(basename -- "$ifile") already owned by $iwg"
      fi
      for claim_file in "$target_dir"/WG-*.md; do
        [[ -f $claim_file ]] || continue
        claim_id=$(basename -- "$claim_file" | cut -d- -f1,2)
        claim_items=$(x_field_get "$claim_file" "Work items" | tr ',' ' ')
        if [[ " $claim_items " == *" $(x_plan_item_id "$ifile") "* ]] && [[ $claim_id != "$id" ]]; then
          x_unlock
          x_die "wg new: item $(basename -- "$ifile") already owned by $claim_id"
        fi
      done
    done
  fi

  if [[ $found == yes ]]; then
    # An existing WG owns its branch and worktree names; never recompute them,
    # because a recomputed stamp can differ from the one already recorded.
    branch=$(x_field_get "$file" Branch | tr -d '`')
    worktree=$(x_field_get "$file" Worktree | tr -d '`')
    local merged
    merged=$(x_wg_merge_items "$(x_field_get "$file" "Work items")" "$items")
    x_field_set "$file" "Work items" "$merged"
  else
    id=$(x_id_next WG "$scope_dir")
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
  # Write back the cached item ownership before releasing the claim lock.
  local wgf
  if (( ${#item_files[@]} > 0 )); then
    for wgf in "${item_files[@]}"; do
      x_field_set "$wgf" WG "$id"
    done
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
        # Tab-separated, like every other machine-readable record here: a path
        # can contain spaces, so a space-separated record is not a format.
        if [[ -n $path ]]; then
          printf 'WORKTREE\t%s\t%s\n' "${branch:-(none)}" "$path"
        fi
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
