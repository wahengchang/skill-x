#!/usr/bin/env bash
# Complete uninstall entry point: remove the current manifest-owned deployment
# and sweep legacy deployments, including skills deleted from later commits.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CLI="$ROOT/bin/skill-x"
LEGACY_INVENTORY="$ROOT/bin/legacy-skills.txt"
REPO_SIGNATURE="skill-x repository"
# shellcheck source=bin/lib/common.sh
. "$ROOT/bin/lib/common.sh"
# shellcheck source=bin/targets/targets.conf
source "$ROOT/bin/targets/targets.conf"

SX_ROOT=$ROOT
SX_ID=$(sx_install_id "$ROOT")
MANIFEST=$(sx_manifest_path "$SX_ID")
RECORDED_ROOT=$(sx_manifest_scalar "$MANIFEST" checkout_path)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/skill-x-uninstall.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
HISTORY_FILE="$TMP/historical-skills.txt"

usage() {
  cat <<'USAGE'
Usage: ./uninstall.sh [--agents claude,codex,opencode] [--remove-checkout] [--yes]

Removes the current skill-x installation plus historical deployments. Historical
skill names are recovered from Git history, with bin/legacy-skills.txt as a
fallback for shallow clones or archives.
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

historical_skill_names() {
  {
    if [[ -f "$LEGACY_INVENTORY" ]]; then
      awk '!/^[[:space:]]*(#|$)/ {print $1}' "$LEGACY_INVENTORY"
    fi

    if [[ -d "$ROOT/commands-src" ]]; then
      find "$ROOT/commands-src" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print |
        while IFS= read -r skill_file; do basename "$(dirname "$skill_file")"; done
    fi

    if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
      git -C "$ROOT" log --all --format= --name-only -- commands-src 2>/dev/null |
        awk -F/ '$1 == "commands-src" && NF >= 3 && $NF == "SKILL.md" {print $2}'
    fi
  } | LC_ALL=C sort -u
}

historical_skill_names > "$HISTORY_FILE"

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
  printf 'Remove skill-x deployments for %s, including historical skills? [y/N] ' "$selected"
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

repo_skill_copy() {
  local skill_file=$1
  [[ -f "$skill_file" ]] || return 1
  grep -Fq "$REPO_SIGNATURE" "$skill_file" 2>/dev/null || return 1
  grep -Fq 'bin/update-check' "$skill_file" 2>/dev/null || return 1
}

historical_skill_path_owned() {
  local path=$1 name=$2 linked target

  if [[ -L "$path" ]]; then
    owned_legacy_link "$path" && return 0
    linked=$(readlink "$path") || return 1
    case "$linked" in
      /*) target=$linked ;;
      *) target="$(dirname "$path")/$linked" ;;
    esac

    # A live link outside the known checkout is removable only when the target
    # still carries this repository's generated skill header.
    if [[ -e "$path" ]]; then
      repo_skill_copy "$target/SKILL.md" && return 0
      return 1
    fi

    # For a dangling pre-manifest link the exact historical name plus the old
    # canonical repository layout is the remaining ownership evidence.
    case "$linked" in
      */commands/"$name"|*/commands-src/"$name") return 0 ;;
    esac
    return 1
  fi

  [[ -d "$path" ]] && repo_skill_copy "$path/SKILL.md"
}

historical_command_link_owned() {
  local path=$1 name=$2 linked target
  [[ -L "$path" ]] || return 1
  owned_legacy_link "$path" && return 0
  linked=$(readlink "$path") || return 1
  case "$linked" in
    /*) target=$linked ;;
    *) target="$(dirname "$path")/$linked" ;;
  esac

  if [[ -e "$path" ]]; then
    grep -Fq "$SKILL_X_MANAGED_MARKER" "$target" 2>/dev/null && return 0
    return 1
  fi

  case "$linked" in
    */opencode-commands/"$name".md) return 0 ;;
  esac
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
# manifest is expected for pre-manifest installations; history cleanup below
# is sufficient in that case.
if [[ -f "$MANIFEST" ]]; then
  cli_args=(uninstall --yes)
  [[ -n "$explicit" ]] && cli_args+=(--agents "$explicit")
  "$CLI" "${cli_args[@]}"
else
  echo 'No installation manifest found; scanning Git history for legacy deployments.'
fi

legacy_removed=0
for agent in ${SKILL_X_ALL_AGENTS[*]}; do
  sx_contains "$agent" $selected || continue
  while IFS= read -r dir; do
    [[ -d "$dir" ]] || continue

    # First remove any link still provably tied to this checkout, including
    # uncommitted/current names not represented in history.
    while IFS= read -r -d '' path; do
      owned_legacy_link "$path" || continue
      rm -f "$path"
      printf '  legacy    %s\n' "$path"
      legacy_removed=$((legacy_removed + 1))
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type l -print0)

    # Then use the historical inventory to recover names that disappeared from
    # the current repository or came from an older checkout path.
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      path="$dir/$name"
      [[ -e "$path" || -L "$path" ]] || continue
      historical_skill_path_owned "$path" "$name" || continue
      if [[ -L "$path" ]]; then rm -f "$path"; else rm -rf "$path"; fi
      printf '  history   %s\n' "$path"
      legacy_removed=$((legacy_removed + 1))
    done < "$HISTORY_FILE"
  done < <(legacy_skill_dirs "$agent")
done

if sx_contains opencode $selected; then
  commands_dir=$(sx_opencode_commands_dir)
  if [[ -d "$commands_dir" ]]; then
    # Marker-carrying regular command copies are always ours.
    while IFS= read -r -d '' path; do
      if [[ -L "$path" ]]; then
        owned_legacy_link "$path" || continue
      elif [[ -f "$path" ]]; then
        grep -Fq "$SKILL_X_MANAGED_MARKER" "$path" 2>/dev/null || continue
      else
        continue
      fi
      rm -f "$path"
      printf '  legacy    %s\n' "$path"
      legacy_removed=$((legacy_removed + 1))
    done < <(find "$commands_dir" -mindepth 1 -maxdepth 1 \( -type l -o -type f \) -print0)

    # Recover dangling command shims for skills removed in older commits.
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      path="$commands_dir/$name.md"
      [[ -L "$path" ]] || continue
      historical_command_link_owned "$path" "$name" || continue
      rm -f "$path"
      printf '  history   %s\n' "$path"
      legacy_removed=$((legacy_removed + 1))
    done < "$HISTORY_FILE"
  fi
fi

history_count=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
printf 'Historical inventory: %s skill name(s). Removed %s legacy deployment path(s).\n' "$history_count" "$legacy_removed"

if (( remove_checkout )); then
  echo "Removing checkout $ROOT"
  rm -rf "$TMP"
  trap - EXIT
  cd /
  exec rm -rf -- "$ROOT"
fi
