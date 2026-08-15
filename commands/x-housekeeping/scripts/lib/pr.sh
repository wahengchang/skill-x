# shellcheck shell=bash
# Pull-request create-or-update.
#
# The provider is deliberately pluggable and optional: when no CLI is available
# the caller is told so in machine-readable form and can fall back to printing
# instructions, instead of the skill inventing a PR that does not exist.
#
# Lookup identifies a PR by head branch *and* head repository owner. A branch
# name alone is not a key: when the branch was pushed to a fork, several open
# PRs against the same base repository can share the name `fix`, and updating
# the wrong one would overwrite somebody else's description.

x_pr_provider() {
  if command -v gh >/dev/null 2>&1; then
    printf 'gh'
  else
    printf 'none'
  fi
}

x_pr_current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || printf ''
}

# Owner of the repository this branch is pushed to — the fork's owner when the
# branch lives on a fork, the base repository's owner otherwise.
x_pr_head_owner() {
  local branch=$1 remote="" url=""
  remote=$(git config --get "branch.$branch.remote" 2>/dev/null || printf '')
  [[ -n $remote ]] || remote=$(git config --get remote.pushDefault 2>/dev/null || printf '')
  [[ -n $remote ]] || remote=origin
  url=$(git remote get-url --push "$remote" 2>/dev/null || printf '')
  [[ -n $url ]] || return 0

  # Handles git@host:owner/repo.git, https://host/owner/repo(.git) and
  # ssh://git@host/owner/repo.git alike by taking the segment before the name.
  local trimmed=${url%.git}
  trimmed=${trimmed%/}
  local rest=${trimmed%/*}
  local owner=${rest##*[:/]}
  if [[ $owner == "$trimmed" || -z $owner ]]; then return 0; fi
  printf '%s' "$owner"
}

# Open PRs as TSV: number, url, head branch, head repo owner. TSV keeps the
# matching in shell string comparisons rather than in a hand-rolled JSON
# parser, and keeps the query itself substitutable in tests.
x_pr_list_tsv() {
  gh pr list --state open --limit 100 \
    --json number,url,headRefName,headRepositoryOwner \
    --jq '.[] | [.number, .url, .headRefName, (.headRepositoryOwner.login // "")] | @tsv' \
    2>/dev/null
}

x_pr_status() {
  local branch=""
  while (( $# )); do
    case $1 in
      --branch) branch=$2; shift 2 ;;
      *) x_die "pr status: unknown option $1" ;;
    esac
  done
  [[ -n $branch ]] || branch=$(x_pr_current_branch)
  local provider; provider=$(x_pr_provider)
  x_emit X_PR_PROVIDER "$provider"
  x_emit X_PR_BRANCH "$branch"
  if [[ $provider == none ]]; then
    x_emit X_PR_STATE no-provider
    return 0
  fi

  local head_owner; head_owner=$(x_pr_head_owner "$branch")
  x_emit X_PR_HEAD_OWNER "${head_owner:-unknown}"

  local listing
  if ! listing=$(x_pr_list_tsv); then
    x_emit X_PR_STATE unavailable
    return 0
  fi

  local number url ref owner
  local matches=() numbers=""
  while IFS=$'\t' read -r number url ref owner; do
    [[ -n $number ]] || continue
    [[ $ref == "$branch" ]] || continue
    # Skip a same-named branch belonging to a different fork. An unknown owner
    # on either side cannot exclude anything, so it is kept as a candidate and
    # resolved by the ambiguity check below.
    if [[ -n $head_owner && -n $owner && $owner != "$head_owner" ]]; then
      continue
    fi
    matches+=("$number"$'\t'"$url"$'\t'"$owner")
    numbers+="${numbers:+,}#$number"
  done <<< "$listing"

  case ${#matches[@]} in
    0) x_emit X_PR_STATE none ;;
    1)
      IFS=$'\t' read -r number url owner <<< "${matches[0]}"
      x_emit X_PR_STATE open
      x_emit X_PR_NUMBER "$number"
      x_emit X_PR_URL "$url"
      x_emit X_PR_HEAD_REPO_OWNER "${owner:-unknown}"
      ;;
    *)
      # Never guess which one to overwrite.
      x_emit X_PR_STATE ambiguous
      x_emit X_PR_CANDIDATES "$numbers"
      ;;
  esac
}

x_pr_upsert() {
  local branch="" base="" title="" body_file="" draft=no
  while (( $# )); do
    case $1 in
      --branch) branch=$2; shift 2 ;;
      --base) base=$2; shift 2 ;;
      --title) title=$2; shift 2 ;;
      --body-file) body_file=$2; shift 2 ;;
      --draft) draft=yes; shift ;;
      *) x_die "pr upsert: unknown option $1" ;;
    esac
  done
  [[ -n $branch ]] || branch=$(x_pr_current_branch)
  [[ -n $base ]] || base=$(x_base_branch)
  x_require_value --title "$title"
  x_require_value --body-file "$body_file"
  [[ -f $body_file ]] || x_die "no such body file: $body_file"

  local provider; provider=$(x_pr_provider)
  if [[ $provider == none ]]; then
    x_emit X_PR_PROVIDER none
    x_emit X_PR_STATE no-provider
    x_emit X_PR_ACTION none
    return 0
  fi

  local status state number url
  status=$(x_pr_status --branch "$branch")
  state=$(printf '%s\n' "$status" | sed -n 's/^X_PR_STATE=//p')
  number=$(printf '%s\n' "$status" | sed -n 's/^X_PR_NUMBER=//p')
  x_emit X_PR_PROVIDER "$provider"
  x_emit X_PR_BRANCH "$branch"
  x_emit X_PR_HEAD_OWNER "$(printf '%s\n' "$status" | sed -n 's/^X_PR_HEAD_OWNER=//p')"

  case $state in
    ambiguous)
      x_die "several open PRs match branch '$branch'; pass --branch or resolve them manually"
      ;;
    unavailable)
      x_die "cannot query pull requests for '$branch'"
      ;;
  esac

  if [[ -n $number ]]; then
    gh pr edit "$number" --title "$title" --body-file "$body_file" >/dev/null
    url=$(printf '%s\n' "$status" | sed -n 's/^X_PR_URL=//p')
    x_emit X_PR_ACTION updated
  else
    local head=$branch head_owner
    head_owner=$(x_pr_head_owner "$branch")
    # gh needs owner:branch to open a PR from a fork.
    if [[ -n $head_owner ]]; then
      local base_owner
      base_owner=$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || printf '')
      if [[ -n $base_owner && $base_owner != "$head_owner" ]]; then
        head="$head_owner:$branch"
      fi
    fi
    local args=(--head "$head" --base "$base" --title "$title" --body-file "$body_file")
    if [[ $draft == yes ]]; then args+=(--draft); fi
    url=$(gh pr create "${args[@]}") || x_die "gh pr create failed"
    url=$(printf '%s\n' "$url" | tr -d '\r' | grep -o 'https://[^ ]*' | tail -1)
    x_emit X_PR_ACTION created
  fi
  x_emit X_PR_STATE open
  x_emit X_PR_URL "$url"
}
