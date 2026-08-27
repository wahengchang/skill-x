#!/usr/bin/env bash
# Complete uninstall entry point: remove the current manifest-owned deployment
# and sweep legacy links left by older versions of this checkout.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CLI="$ROOT/bin/skill-x"
# shellcheck source=bin/lib/common.sh
. "$ROOT/bin/lib/common.sh"
# shellcheck source=bin/targets/targets.conf
source "$ROOT/bin/targets/targets.conf"

SX_ROOT=$ROOT
SX_ID=$(sx_install_id "$ROOT")
MANIFEST=$(sx_manifest_path "$SX_ID")
RECORDED_ROOT=$(sx_manifest_scalar "$MANIFEST" checkout_path)

usage() {
  cat <<'USAGE'
Usage: ./uninstall.sh [--agents claude,codex,opencode] [--remove-checkout] [--yes]

Removes the current skill-x installation plus legacy skill/command links that
older versions of this same checkout may have left behind.
USAGE
}

explicit=""
remove_checkout=0
assume_yes=0
while (( $# )); do
  case "$1" in
    --agents) explicit=${2:-}; shift 2 ;;
    --agents=*) explicit=${1#*=}; shift ;;
    --remove-checkout) remove_checkout=1; shift ;;
    --yes|-y) assume_yes=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) sx_die "unknown option for uninstall: $1" ;;
  esac
done

selected="${SKILL_X_ALL_AGENTS[*]}"
[[ -n "$explicit" ]] && selected=$(sx_parse_agents "$explicit")
[[ -n "$selected" ]] || sx_die 'no agents selected'

# Return success when deleting the checkout would discard local content. This
# mirrors the lifecycle CLI safety rule while allowing generated build outputs.
checkout_has_local_content() {
  local root=$1 status path allowed skip entry
  status=$(git -C "$root" status --porcelain --untracked-files=all 2>/dev/null) || return 0
  [[ -n "$status" ]] && return 0

  local -a disposable=("$CANONICAL_DEST")
  for entry in "${TRANSFORMED_TARGETS[@]}"; do
    disposable+=("${entry##*:}")
  done

  while IFS= read -r -d '' path; do
    skip=0
    for allowed in "${disposable[@]}"; do
      allowed=${allowed%/}
      if [[ "$path" == "$allowed" || "$path" == "$allowed/"* ]]; then
        skip=1
        break
      fi
    done
    (( skip )) || return 0
  done < <(git -C "$root" ls-files --others --ignored --exclude-standard -z 2>/dev/null)
  return 1
}

if (( remove_checkout )) && checkout_has_local_content "$ROOT"; then
  sx_die "refusing to delete a dirty checkout at $ROOT
  Commit, stash or remove local content first:
    git -C $ROOT status --short --ignored"
fi

if (( ! assume_yes )) && [[ -t 0 && -t 1 ]]; then
  reply=""
  printf 'Remove skill-x deployments for %s, including legacy links? [y/N] ' "$selected"
  read -r reply || reply=""
  [[ "$reply" == [yY]* ]] || { echo 'Uninstall declined; nothing changed.'; exit 0; }
fi

# Keep the old checkout path as an ownership proof if the repository moved.
legacy_roots=("$ROOT")
if [[ -n "$RECORDED_ROOT" && "$RECORDED_ROOT" != "$ROOT" ]]; then
  legacy_roots+=("$RECORDED_ROOT")
fi

owned_legacy_link() {
  local path=$1 linked root
  [[ -L "$path" ]] || return 1
  linked=$(readlink "$path") || return 1
  [[ "$linked" == /* ]] || return 1
  for root in "${legacy_roots[@]}"; do
    root=${root%/}
    [[ "$linked" == "$root/"* ]] && return 0
  done
  return 1
}

legacy_skill_dirs() {
  case "$1" in
    claude) printf '%s\n' "$HOME/.claude/skills" ;;
    codex)
      # Sweep both the canonical and historical compatibility path regardless
      # of the current SKILL_X_CODEX_COMPAT setting.
      printf '%s\n' "$HOME/.agents/skills" "$HOME/.codex/skills"
      ;;
    opencode) printf '%s\n' "$HOME/.config/opencode/skills" ;;
    *) return 1 ;;
  esac
}

# Let the lifecycle CLI remove manifest-owned paths and state first. A missing
# manifest is expected for pre-manifest installations; the legacy sweep below
# is sufficient in that case.
if [[ -f "$MANIFEST" ]]; then
  cli_args=(uninstall --yes)
  [[ -n "$explicit" ]] && cli_args+=(--agents "$explicit")
  "$CLI" "${cli_args[@]}"
else
  echo 'No installation manifest found; scanning legacy deployments tied to this checkout.'
fi

legacy_removed=0
for agent in ${SKILL_X_ALL_AGENTS[*]}; do
  sx_contains "$agent" $selected || continue
  while IFS= read -r dir; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' path; do
      owned_legacy_link "$path" || continue
      rm -f "$path"
      printf '  legacy    %s\n' "$path"
      legacy_removed=$((legacy_removed + 1))
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type l -print0)
  done < <(legacy_skill_dirs "$agent")
done

if sx_contains opencode $selected; then
  commands_dir=$(sx_opencode_commands_dir)
  if [[ -d "$commands_dir" ]]; then
    while IFS= read -r -d '' path; do
      if [[ -L "$path" ]]; then
        owned_legacy_link "$path" || continue
      elif [[ -f "$path" ]]; then
        grep -q "$SKILL_X_MANAGED_MARKER" "$path" 2>/dev/null || continue
      else
        continue
      fi
      rm -f "$path"
      printf '  legacy    %s\n' "$path"
      legacy_removed=$((legacy_removed + 1))
    done < <(find "$commands_dir" -mindepth 1 -maxdepth 1 \( -type l -o -type f \) -print0)
  fi
fi

printf 'Removed %s legacy deployment path(s).\n' "$legacy_removed"

if (( remove_checkout )); then
  echo "Removing checkout $ROOT"
  cd /
  exec rm -rf -- "$ROOT"
fi
