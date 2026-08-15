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
            printf 'ITEM ORPHAN worktree %s missing-directory\n' "$path"
            blocked=$(( blocked + 1 ))
          elif [[ -n $(git -C "$path" status --porcelain 2>/dev/null) ]]; then
            printf 'ITEM DIRTY worktree %s uncommitted-changes\n' "$path"
            blocked=$(( blocked + 1 ))
          elif [[ -n $branch && $branch != "(detached)" ]] &&
               [[ -n $(git -C "$X_MAIN_ROOT" log --oneline "$base_ref..$branch" 2>/dev/null) ]]; then
            printf 'ITEM UNMERGED worktree %s branch=%s\n' "$path" "$branch"
            blocked=$(( blocked + 1 ))
          else
            printf 'ITEM SAFE worktree %s branch=%s\n' "$path" "${branch:-none}"
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
      printf 'ITEM UNMERGED branch %s not-integrated\n' "$b"
      blocked=$(( blocked + 1 ))
    else
      printf 'ITEM SAFE branch %s integrated\n' "$b"
      safe=$(( safe + 1 ))
    fi
  done < <(git -C "$X_MAIN_ROOT" for-each-ref --format='%(refname:short)' 'refs/heads/x/*' 2>/dev/null)

  # 3. Standalone runtime scratch older than the retention window
  local dir
  if [[ -d $X_RUNTIME ]]; then
    while IFS= read -r dir; do
      [[ -n $dir ]] || continue
      if [[ $dir == "$X_RUNTIME" ]]; then continue; fi
      if [[ -n $(find "$dir" -maxdepth 0 -mtime +"$older_than" 2>/dev/null) ]]; then
        printf 'ITEM SAFE runtime %s older-than-%sd\n' "$dir" "$older_than"
        safe=$(( safe + 1 ))
      else
        printf 'ITEM ACTIVE runtime %s recent\n' "$dir"
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
      printf 'ITEM SAFE cycle-tmp %s scratch\n' "$cycle/tmp"
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

  local removed=0 kind target class rest
  while read -r _ class kind target rest; do
    [[ $class == SAFE ]] || continue
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
