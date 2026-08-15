# shellcheck shell=bash
# Pull-request create-or-update.
#
# The provider is deliberately pluggable and optional: when no CLI is available
# the caller is told so in machine-readable form and can fall back to printing
# instructions, instead of the skill inventing a PR that does not exist.

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

  local json
  if ! json=$(gh pr list --head "$branch" --state open --limit 1 \
                --json number,url,title 2>/dev/null); then
    x_emit X_PR_STATE unavailable
    return 0
  fi
  local number url
  number=$(printf '%s' "$json" | sed -n 's/.*"number":\([0-9]*\).*/\1/p')
  url=$(printf '%s' "$json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
  if [[ -n $number ]]; then
    x_emit X_PR_STATE open
    x_emit X_PR_NUMBER "$number"
    x_emit X_PR_URL "$url"
  else
    x_emit X_PR_STATE none
  fi
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
  x_emit X_PR_PROVIDER "$provider"
  if [[ $provider == none ]]; then
    x_emit X_PR_STATE no-provider
    x_emit X_PR_ACTION none
    return 0
  fi

  local status number
  status=$(x_pr_status --branch "$branch")
  number=$(printf '%s\n' "$status" | sed -n 's/^X_PR_NUMBER=//p')

  local url
  if [[ -n $number ]]; then
    gh pr edit "$number" --title "$title" --body-file "$body_file" >/dev/null
    url=$(printf '%s\n' "$status" | sed -n 's/^X_PR_URL=//p')
    x_emit X_PR_ACTION updated
  else
    local args=(--head "$branch" --base "$base" --title "$title" --body-file "$body_file")
    [[ $draft == yes ]] && args+=(--draft)
    url=$(gh pr create "${args[@]}") || x_die "gh pr create failed"
    url=$(printf '%s\n' "$url" | tr -d '\r' | grep -o 'https://[^ ]*' | tail -1)
    x_emit X_PR_ACTION created
  fi
  x_emit X_PR_STATE open
  x_emit X_PR_URL "$url"
}
