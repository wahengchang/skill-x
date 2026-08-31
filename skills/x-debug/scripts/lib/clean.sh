# shellcheck shell=bash
# Housekeeping: classify execution residue, then delete only what is provably
# safe. Classification and deletion are separate commands so the reasoning is
# always inspectable before anything is destroyed.
#
# Classes:
#   SAFE     — proven finished: clean worktree, integrated branch, expired scratch
#   DIRTY    — uncommitted changes present
#   UNMERGED — commits that do not exist on the base branch
#   ACTIVE   — still in use / too recent
#   ORPHAN   — Git metadata pointing at a path that no longer exists

# A deletable target must live under the directory its kind belongs to.
# Branches are refs, not paths, and are checked by name instead.
x_clean_target_is_contained() {
  local kind=$1 target=$2
  x_resolve_paths
  case $kind in
    worktree) [[ $target == "$X_WORKTREES"/* ]] ;;
    runtime) [[ $target == "$X_RUNTIME"/* ]] ;;
    cycle-tmp) [[ $target == "$X_ACTIVE"/*/tmp ]] ;;
    branch) [[ $target == x/* ]] ;;
    *) return 1 ;;
  esac
}

# A scratch directory that still holds unfinished planning documents is live
# work, whatever its age. Standalone WGs and work items live under runtime/,
# so an age-only rule would eventually rm -rf a Work Group that is still open.
x_clean_dir_holds_live_work() {
  local dir=$1 file kind status
  while IFS= read -r file; do
    [[ -n $file ]] || continue
    kind=item
    if [[ $(basename -- "$file") == WG-* ]]; then kind=WG; fi
    status=$(x_field_get "$file" Status 2>/dev/null || printf '')
    if ! x_status_is_terminal "$kind" "$status"; then
      return 0
    fi
  done < <(find "$dir" -type f \( -name 'WG-*.md' -o -name 'IS-*.md' -o -name 'SP-*.md' \) 2>/dev/null)
  return 1
}

x_clean_scan() {
  local base="" older_than=7
  while (( $# )); do
    case $1 in
      --base) base=$2; shift 2 ;;
      --older-than) older_than=$2; shift 2 ;;
      *) x_die "clean scan: unknown option $1" ;;
    esac
  done
  x_resolve_paths
  [[ -n $base ]] || base=$(x_base_branch)
  local base_ref; base_ref=$(x_base_ref "$base")
  x_emit X_CLEAN_BASE "$base_ref"

  local safe=0 blocked=0

  # 1. Worktrees registered under .dev-hub/worktrees/
  local path="" branch=""
  while IFS= read -r line; do
    case $line in
      "worktree "*) path=${line#worktree }; branch="" ;;
      "branch "*) branch=${line#branch refs/heads/} ;;
      "detached") branch="(detached)" ;;
      "")
        if [[ -n $path && $path == "$X_WORKTREES"/* ]]; then
          if [[ ! -d $path ]]; then
            printf 'ITEM\tORPHAN\tworktree\t%s\tmissing-directory\n' "$path"
            blocked=$(( blocked + 1 ))
          elif [[ -n $(git -C "$path" status --porcelain 2>/dev/null) ]]; then
            printf 'ITEM\tDIRTY\tworktree\t%s\tuncommitted-changes\n' "$path"
            blocked=$(( blocked + 1 ))
          elif [[ -n $branch && $branch != "(detached)" ]] &&
               [[ -n $(git -C "$X_MAIN_ROOT" log --oneline "$base_ref..$branch" 2>/dev/null) ]]; then
            printf 'ITEM\tUNMERGED\tworktree\t%s\tbranch=%s\n' "$path" "$branch"
            blocked=$(( blocked + 1 ))
          else
            printf 'ITEM\tSAFE\tworktree\t%s\tbranch=%s\n' "$path" "${branch:-none}"
            safe=$(( safe + 1 ))
          fi
        fi
        path=""
        ;;
    esac
  done < <(git -C "$X_MAIN_ROOT" worktree list --porcelain; printf '\n')

  # 2. Local x/* branches with no worktree left
  local b checked_out
  checked_out=$(git -C "$X_MAIN_ROOT" worktree list --porcelain |
                sed -n 's/^branch refs\/heads\///p')
  while IFS= read -r b; do
    [[ -n $b ]] || continue
    if printf '%s\n' "$checked_out" | grep -Fxq "$b"; then continue; fi
    if [[ -n $(git -C "$X_MAIN_ROOT" log --oneline "$base_ref..$b" 2>/dev/null) ]]; then
      printf 'ITEM\tUNMERGED\tbranch\t%s\tnot-integrated\n' "$b"
      blocked=$(( blocked + 1 ))
    else
      printf 'ITEM\tSAFE\tbranch\t%s\tintegrated\n' "$b"
      safe=$(( safe + 1 ))
    fi
  done < <(git -C "$X_MAIN_ROOT" for-each-ref --format='%(refname:short)' 'refs/heads/x/*' 2>/dev/null)

  # 3. Standalone runtime scratch older than the retention window
  local dir
  if [[ -d $X_RUNTIME ]]; then
    while IFS= read -r dir; do
      [[ -n $dir ]] || continue
      if [[ $dir == "$X_RUNTIME" ]]; then continue; fi
      if x_clean_dir_holds_live_work "$dir"; then
        printf 'ITEM\tACTIVE\truntime\t%s\tholds-live-work\n' "$dir"
      elif [[ -n $(find "$dir" -maxdepth 0 -mtime +"$older_than" 2>/dev/null) ]]; then
        printf 'ITEM\tSAFE\truntime\t%s\tolder-than-%sd\n' "$dir" "$older_than"
        safe=$(( safe + 1 ))
      else
        printf 'ITEM\tACTIVE\truntime\t%s\trecent\n' "$dir"
      fi
    done < <(find "$X_RUNTIME" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null)
  fi

  # 4. Cycle-local tmp/ contents of active Cycles
  local cycle
  if [[ -d $X_ACTIVE ]]; then
    while IFS= read -r cycle; do
      [[ -n $cycle ]] || continue
      [[ -d $cycle/tmp ]] || continue
      [[ -n $(find "$cycle/tmp" -mindepth 1 -maxdepth 1 2>/dev/null) ]] || continue
      printf 'ITEM\tSAFE\tcycle-tmp\t%s\tscratch\n' "$cycle/tmp"
      safe=$(( safe + 1 ))
    done < <(find "$X_ACTIVE" -mindepth 1 -maxdepth 1 -type d -name 'cycle-*' 2>/dev/null)
  fi

  x_emit X_CLEAN_SAFE "$safe"
  x_emit X_CLEAN_BLOCKED "$blocked"
}

x_clean_apply() {
  local dry_run=no base="" older_than=7
  while (( $# )); do
    case $1 in
      --dry-run) dry_run=yes; shift ;;
      --base) base=$2; shift 2 ;;
      --older-than) older_than=$2; shift 2 ;;
      *) x_die "clean apply: unknown option $1" ;;
    esac
  done
  x_resolve_paths
  local scan_args=(--older-than "$older_than")
  if [[ -n $base ]]; then scan_args+=(--base "$base"); fi
  local scan
  scan=$(x_clean_scan "${scan_args[@]}")
  printf '%s\n' "$scan"

  # Tab-separated, so a repository path containing a space cannot truncate the
  # target. Reading these records with default word splitting turned
  # "/repo/.dev-hub/runtime/x" under "/home/u/proj v2" into "/home/u/proj" —
  # a real sibling directory, passed straight to rm -rf.
  local removed=0 kind target class detail
  while IFS=$'\t' read -r _ class kind target detail; do
    [[ $class == SAFE ]] || continue
    [[ -n $target ]] || continue
    # Independent of the parse: nothing outside the directory a kind belongs to
    # is ever deletable, so a future field change cannot reach the filesystem.
    if ! x_clean_target_is_contained "$kind" "$target"; then
      printf 'SKIPPED %s %s outside-dev-hub\n' "$kind" "$target"
      continue
    fi
    if [[ $dry_run == yes ]]; then
      printf 'WOULD-REMOVE %s %s\n' "$kind" "$target"
      continue
    fi
    case $kind in
      worktree)
        # Re-check immediately before deleting: the scan may be seconds old.
        if [[ -n $(git -C "$target" status --porcelain 2>/dev/null) ]]; then
          printf 'SKIPPED worktree %s became-dirty\n' "$target"
          continue
        fi
        if git -C "$X_MAIN_ROOT" worktree remove "$target" >/dev/null 2>&1; then
          printf 'REMOVED worktree %s\n' "$target"
          removed=$(( removed + 1 ))
        else
          printf 'SKIPPED worktree %s removal-failed\n' "$target"
        fi
        ;;
      branch)
        # -d only; an unmerged branch must never be force-deleted here.
        if git -C "$X_MAIN_ROOT" branch -d "$target" >/dev/null 2>&1; then
          printf 'REMOVED branch %s\n' "$target"
          removed=$(( removed + 1 ))
        else
          printf 'SKIPPED branch %s not-safely-deletable\n' "$target"
        fi
        ;;
      runtime)
        rm -rf -- "$target"
        printf 'REMOVED runtime %s\n' "$target"
        removed=$(( removed + 1 ))
        ;;
      cycle-tmp)
        find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
        printf 'REMOVED cycle-tmp %s\n' "$target"
        removed=$(( removed + 1 ))
        ;;
    esac
  done <<< "$scan"

  if [[ $dry_run == no ]]; then
    git -C "$X_MAIN_ROOT" worktree prune >/dev/null 2>&1 || true
  fi
  x_emit X_CLEAN_REMOVED "$removed"
  x_emit X_CLEAN_DRY_RUN "$dry_run"
}
