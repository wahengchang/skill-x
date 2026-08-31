# shellcheck shell=bash
# Review-target fingerprinting.
#
# An approval must be bound to *content*, not to a timestamp. The fingerprint is
# the Git tree object for the exact working state that was reviewed — committed
# and uncommitted changes alike — so "was this approved?" becomes an equality
# check a script can make, and any later edit invalidates it automatically.

x_fingerprint() {
  local base="" verbose_base
  while (( $# )); do
    case $1 in
      --base) base=$2; shift 2 ;;
      *) x_die "fingerprint: unknown option $1" ;;
    esac
  done
  x_resolve_paths
  [[ -n $base ]] || base=$(x_base_branch)
  verbose_base=$(x_base_ref "$base")

  local top; top=$(git rev-parse --show-toplevel) || x_die "not inside a worktree"
  local head merge_base tree dirty=no

  head=$(git -C "$top" rev-parse HEAD 2>/dev/null || printf 'none')
  merge_base=$(git -C "$top" merge-base "$verbose_base" HEAD 2>/dev/null || printf 'none')
  if [[ -n $(git -C "$top" status --porcelain 2>/dev/null) ]]; then dirty=yes; fi

  # Snapshot the full working state into a throwaway index. The real index is
  # never touched, so this is safe to run at any moment during implementation.
  # The hub's own ephemeral directories are excluded explicitly: the snapshot
  # must not depend on scratch this command itself creates, and the exclusion
  # cannot rely on .gitignore having been set up first.
  x_ensure_gitignore >/dev/null
  mkdir -p "$X_RUNTIME/.tmp"
  local index; index=$(mktemp "$X_RUNTIME/.tmp/index.XXXXXX")
  rm -f "$index"
  if [[ $head == none ]]; then
    GIT_INDEX_FILE="$index" git -C "$top" read-tree --empty
  else
    GIT_INDEX_FILE="$index" git -C "$top" read-tree HEAD
  fi
  if ! GIT_INDEX_FILE="$index" git -C "$top" add -A 2>/dev/null; then
    rm -f "$index"
    x_die "cannot snapshot the working tree (unmerged paths?)"
  fi
  GIT_INDEX_FILE="$index" git -C "$top" rm -r --cached --quiet --ignore-unmatch -- \
    .dev-hub/active .dev-hub/runtime .dev-hub/worktrees >/dev/null 2>&1 || true
  if ! tree=$(GIT_INDEX_FILE="$index" git -C "$top" write-tree 2>/dev/null); then
    rm -f "$index"
    x_die "cannot write a tree for the working state (resolve conflicts first)"
  fi
  rm -f "$index"

  x_emit X_BASE "$base"
  x_emit X_BASE_REF "$verbose_base"
  x_emit X_MERGE_BASE "$merge_base"
  x_emit X_HEAD "$head"
  x_emit X_TREE "$tree"
  x_emit X_DIRTY "$dirty"
  x_emit X_FINGERPRINT "${merge_base:0:12}:${tree:0:12}"
}

# Compare the current content against a recorded fingerprint. FRESH means the
# approval still describes what is on disk; STALE means it must be re-reviewed.
x_fingerprint_verify() {
  local expect="" base=""
  while (( $# )); do
    case $1 in
      --expect) expect=$2; shift 2 ;;
      --base) base=$2; shift 2 ;;
      *) x_die "fingerprint verify: unknown option $1" ;;
    esac
  done
  x_require_value --expect "$expect"
  local out actual
  if [[ -n $base ]]; then
    out=$(x_fingerprint --base "$base")
  else
    out=$(x_fingerprint)
  fi
  printf '%s\n' "$out"
  actual=$(printf '%s\n' "$out" | sed -n 's/^X_FINGERPRINT=//p')
  if [[ $actual == "$expect" ]]; then
    x_emit X_REVIEW_FRESHNESS FRESH
  else
    x_emit X_REVIEW_FRESHNESS STALE
    return 1
  fi
}
