#!/usr/bin/env bash
# Shared helpers for the skill-x lifecycle CLI. Sourced, never executed.
#
# Everything that has to agree between `bin/skill-x`, the compatibility
# wrappers and the update-check hook lives here: which agents exist, where each
# one reads skills from, where per-installation state is kept, and how the
# installation manifest is written and read back.

# shellcheck shell=bash

SKILL_X_LIB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SKILL_X_ALL_AGENTS=(claude codex opencode)
SKILL_X_MANAGED_MARKER="skill-x-managed-command"
SKILL_X_MANIFEST_SCHEMA=1

sx_die() { printf 'skill-x: %s\n' "$*" >&2; exit 1; }
sx_warn() { printf 'skill-x: %s\n' "$*" >&2; }

sx_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

sx_contains() {
  local needle=$1 item
  shift
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

# ---------------------------------------------------------------------------
# Agents
# ---------------------------------------------------------------------------

sx_is_agent() { sx_contains "$1" "${SKILL_X_ALL_AGENTS[@]}"; }

# Skill discovery directories for one agent, most canonical first.
#
# `~/.agents/skills` is the documented cross-agent Codex path; `~/.codex/skills`
# stays as an explicitly identified compatibility target until a real Codex CLI
# run confirms which one it loads (see ARCHITECTURE.md). Set
# SKILL_X_CODEX_COMPAT=0 to drop the compatibility path.
sx_agent_skill_dirs() {
  case "$1" in
    claude) printf '%s\n' "$HOME/.claude/skills" ;;
    codex)
      printf '%s\n' "$HOME/.agents/skills"
      [[ "${SKILL_X_CODEX_COMPAT:-1}" == 0 ]] || printf '%s\n' "$HOME/.codex/skills"
      ;;
    opencode) printf '%s\n' "$HOME/.config/opencode/skills" ;;
    *) return 1 ;;
  esac
}

sx_opencode_commands_dir() { printf '%s\n' "$HOME/.config/opencode/commands"; }

sx_agent_binary() {
  case "$1" in
    claude) printf 'claude\n' ;;
    codex) printf 'codex\n' ;;
    opencode) printf 'opencode\n' ;;
    *) return 1 ;;
  esac
}

# Print the detected version of an agent, or nothing when it is not installed.
# Never allowed to block: the binary gets no stdin and a timeout when available.
sx_agent_version() {
  local agent=$1 binary raw
  binary=$(sx_agent_binary "$agent") || return 1
  command -v "$binary" >/dev/null 2>&1 || return 1
  if command -v timeout >/dev/null 2>&1; then
    raw=$(timeout 10 "$binary" --version </dev/null 2>/dev/null | head -n 1 || true)
  else
    raw=$("$binary" --version </dev/null 2>/dev/null | head -n 1 || true)
  fi
  printf '%s\n' "${raw//$'\r'/}"
}

sx_invocation_syntax() {
  case "$1" in
    claude) printf '/<skill>\n' ;;
    codex) printf '$<skill> (or the /skills menu)\n' ;;
    opencode) printf '/<skill>\n' ;;
  esac
}

# Parse a comma or space separated agent list into canonical order.
sx_parse_agents() {
  local raw=$1 token agent selected=() out=()
  raw=${raw//,/ }
  for token in $raw; do
    [[ -n "$token" ]] || continue
    sx_is_agent "$token" || sx_die "unknown agent: $token (expected ${SKILL_X_ALL_AGENTS[*]})"
    selected+=("$token")
  done
  for agent in "${SKILL_X_ALL_AGENTS[@]}"; do
    sx_contains "$agent" "${selected[@]+"${selected[@]}"}" && out+=("$agent")
  done
  printf '%s\n' "${out[*]+"${out[*]}"}"
}

# ---------------------------------------------------------------------------
# Installation identity and state
# ---------------------------------------------------------------------------

sx_hash() {
  local input=$1
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$input" | sha256sum | awk '{print substr($1, 1, 12)}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$input" | shasum -a 256 | awk '{print substr($1, 1, 12)}'
  else
    # git is already a hard dependency of every code path that needs an id.
    printf '%s' "$input" | git hash-object --stdin | awk '{print substr($1, 1, 12)}'
  fi
}

# Base directory holding one subdirectory per installation.
sx_state_root() {
  local base=${SKILL_X_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}}
  printf '%s/skill-x\n' "$base"
}

# State directory for one installation. SKILL_X_STATE_DIR pins it explicitly
# (used by tests and by anyone who kept the pre-lifecycle layout).
sx_state_dir() {
  if [[ -n "${SKILL_X_STATE_DIR:-}" ]]; then
    printf '%s\n' "$SKILL_X_STATE_DIR"
    return
  fi
  printf '%s/%s\n' "$(sx_state_root)" "$1"
}

sx_manifest_path() { printf '%s/install.json\n' "$(sx_state_dir "$1")"; }

# Every manifest known to this HOME, one path per line.
sx_all_manifests() {
  local dir
  if [[ -n "${SKILL_X_STATE_DIR:-}" ]]; then
    [[ -f "$SKILL_X_STATE_DIR/install.json" ]] && printf '%s\n' "$SKILL_X_STATE_DIR/install.json"
    return 0
  fi
  local root
  root=$(sx_state_root)
  [[ -d "$root" ]] || return 0
  while IFS= read -r dir; do
    [[ -f "$dir/install.json" ]] && printf '%s\n' "$dir/install.json"
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)
  return 0
}

sx_git_dir() {
  local root=$1 dir
  dir=$(git -C "$root" rev-parse --git-dir 2>/dev/null) || return 1
  case "$dir" in
    /*) printf '%s\n' "$dir" ;;
    *) printf '%s/%s\n' "$root" "$dir" ;;
  esac
}

# Stable identity for one checkout.
#
# The id lives inside .git/ so that moving or renaming the checkout keeps the
# same installation — that is what makes a moved checkout diagnosable instead
# of leaving an unidentifiable pile of stale absolute symlinks. Checkouts
# without a .git (pinned image copies) fall back to hashing the path.
sx_install_id() {
  local root=$1 git_dir="" id_file="" id="" manifest recorded
  if git_dir=$(sx_git_dir "$root"); then
    id_file="$git_dir/skill-x-install-id"
    if [[ -f "$id_file" ]]; then
      read -r id < "$id_file" || id=""
      if [[ "$id" =~ ^[0-9a-f]{8,}$ ]]; then
        printf '%s\n' "$id"
        return 0
      fi
    fi
  fi

  # A fresh clone over an old checkout path adopts the existing manifest rather
  # than orphaning it behind a new id.
  while IFS= read -r manifest; do
    recorded=$(sx_manifest_scalar "$manifest" checkout_path)
    if [[ -n "$recorded" && "$recorded" == "$root" ]]; then
      id=$(sx_manifest_scalar "$manifest" installation_id)
      break
    fi
  done < <(sx_all_manifests)

  [[ -n "$id" ]] || id=$(sx_hash "$root")
  if [[ -n "$id_file" ]]; then
    printf '%s\n' "$id" > "$id_file" 2>/dev/null || true
  fi
  printf '%s\n' "$id"
}

# ---------------------------------------------------------------------------
# Manifest reading
# ---------------------------------------------------------------------------

sx_manifest_scalar() {
  [[ -f "$1" ]] || return 0
  awk -f "$SKILL_X_LIB_DIR/manifest.awk" -v mode=scalar -v key="$2" "$1"
}

sx_manifest_array() {
  [[ -f "$1" ]] || return 0
  awk -f "$SKILL_X_LIB_DIR/manifest.awk" -v mode=array -v key="$2" "$1"
}

sx_manifest_map() {
  [[ -f "$1" ]] || return 0
  awk -f "$SKILL_X_LIB_DIR/manifest.awk" -v mode=map -v key="$2" "$1"
}

# agent<TAB>kind<TAB>path<TAB>target, one managed entry per line.
sx_manifest_entries() {
  [[ -f "$1" ]] || return 0
  awk -f "$SKILL_X_LIB_DIR/manifest.awk" -v mode=entries "$1"
}

# ---------------------------------------------------------------------------
# JSON writing
# ---------------------------------------------------------------------------

sx_json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

sx_json_array() {
  local first=1 item out='['
  for item in "$@"; do
    (( first )) || out+=', '
    out+="\"$(sx_json_escape "$item")\""
    first=0
  done
  printf '%s]' "$out"
}

# Pairs come in as name value name value ...
sx_json_map() {
  local first=1 out='{'
  while (( $# >= 2 )); do
    (( first )) || out+=', '
    out+="\"$(sx_json_escape "$1")\": \"$(sx_json_escape "$2")\""
    first=0
    shift 2
  done
  printf '%s}' "$out"
}

sx_json_bool() { if [[ "$1" == 1 || "$1" == true ]]; then printf 'true'; else printf 'false'; fi; }

# ---------------------------------------------------------------------------
# Manifest writing
# ---------------------------------------------------------------------------

# sx_write_manifest <manifest-path> <entries-tsv>
#
# Reads the description of the installation from SX_* globals so the caller can
# assemble it once. Timestamps not supplied by the caller are carried over from
# the previous manifest, which is what makes "last successful sync" meaningful.
sx_write_manifest() {
  local manifest=$1 entries=$2
  local dir tmp previous_install previous_sync previous_update
  dir=$(dirname "$manifest")
  mkdir -p "$dir"

  previous_install=$(sx_manifest_scalar "$manifest" last_install)
  previous_sync=$(sx_manifest_scalar "$manifest" last_sync)
  previous_update=$(sx_manifest_scalar "$manifest" last_update)

  local last_install=${SX_LAST_INSTALL:-$previous_install}
  local last_sync=${SX_LAST_SYNC:-$previous_sync}
  local last_update=${SX_LAST_UPDATE:-$previous_update}

  local versions=()
  local agent
  for agent in "${SKILL_X_ALL_AGENTS[@]}"; do
    versions+=("$agent" "$(sx_agent_version_cached "$agent")")
  done

  local -a agent_list=() skill_list=()
  local line
  read -r -a agent_list <<< "${SX_AGENTS:-}"
  while IFS= read -r line; do
    [[ -n "$line" ]] && skill_list+=("$line")
  done <<< "${SX_SKILLS:-}"

  tmp="$manifest.tmp.$$"
  {
    printf '{\n'
    printf '  "schema": %s,\n' "$SKILL_X_MANIFEST_SCHEMA"
    printf '  "installation_id": "%s",\n' "$(sx_json_escape "$SX_ID")"
    printf '  "repository_url": "%s",\n' "$(sx_json_escape "${SX_REPO_URL:-}")"
    printf '  "checkout_path": "%s",\n' "$(sx_json_escape "$SX_ROOT")"
    printf '  "installed_commit": "%s",\n' "$(sx_json_escape "${SX_COMMIT:-}")"
    printf '  "agents": %s,\n' "$(sx_json_array ${agent_list[@]+"${agent_list[@]}"})"
    printf '  "agent_versions": %s,\n' "$(sx_json_map "${versions[@]}")"
    printf '  "opencode_mode": "%s",\n' "$(sx_json_escape "${SX_OPENCODE_MODE:-}")"
    printf '  "skills": %s,\n' "$(sx_json_array ${skill_list[@]+"${skill_list[@]}"})"
    printf '  "last_install": "%s",\n' "$(sx_json_escape "$last_install")"
    printf '  "last_sync": "%s",\n' "$(sx_json_escape "$last_sync")"
    printf '  "last_update": "%s",\n' "$(sx_json_escape "$last_update")"
    printf '  "entries": [\n'
    local first=1 agent_name kind path target
    while IFS=$'\t' read -r agent_name kind path target; do
      [[ -n "$path" ]] || continue
      (( first )) || printf ',\n'
      printf '    {"agent": "%s", "kind": "%s", "path": "%s", "target": "%s"}' \
        "$(sx_json_escape "$agent_name")" "$(sx_json_escape "$kind")" \
        "$(sx_json_escape "$path")" "$(sx_json_escape "$target")"
      first=0
    done < "$entries"
    (( first )) || printf '\n'
    printf '  ]\n'
    printf '}\n'
  } > "$tmp"
  mv "$tmp" "$manifest"
}

# Agent versions are probed at most once per process: install, sync and status
# all want them and each probe shells out to a real binary.
sx_agent_version_cached() {
  local agent=$1 var="SX_VERSION_CACHE_${agent}"
  if [[ -n "${!var+set}" ]]; then
    printf '%s' "${!var}"
    return 0
  fi
  local value
  value=$(sx_agent_version "$agent" 2>/dev/null) || value=""
  printf -v "$var" '%s' "$value"
  printf '%s' "$value"
}

# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

sx_is_git_repo() { git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }

sx_git_commit() { git -C "$1" rev-parse HEAD 2>/dev/null || true; }

sx_git_branch() { git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null || true; }

sx_git_remote_url() { git -C "$1" remote get-url origin 2>/dev/null || true; }

# remote<TAB>branch<TAB>remote-tracking ref for the tracked upstream, or nothing.
#
# Resolved from the branch configuration rather than from `@{upstream}`: the
# remote-tracking ref can be missing (pruned, or never fetched in a shallow or
# copied checkout) and rev-parse then fails while still printing "@{upstream}"
# on stdout, which is exactly how a checkout ends up reporting nonsense.
sx_git_upstream_parts() {
  local root=$1 branch remote merge
  branch=$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null) || return 0
  remote=$(git -C "$root" config --get "branch.$branch.remote" 2>/dev/null) || return 0
  merge=$(git -C "$root" config --get "branch.$branch.merge" 2>/dev/null) || return 0
  [[ -n "$remote" && -n "$merge" ]] || return 0
  merge=${merge#refs/heads/}
  printf '%s\t%s\t%s/%s\n' "$remote" "$merge" "$remote" "$merge"
}

# Tracked modifications only. A fast-forward cannot silently discard untracked
# files — git refuses when one is in the way — so they must not block updates.
sx_git_dirty() {
  local status
  status=$(git -C "$1" status --porcelain --untracked-files=no 2>/dev/null) || return 1
  [[ -n "$status" ]]
}

# Anything git would lose if the checkout were deleted, untracked files included.
sx_git_has_local_content() {
  local status
  status=$(git -C "$1" status --porcelain --untracked-files=normal 2>/dev/null) || return 1
  [[ -n "$status" ]]
}

sx_skill_names() {
  local source=${2:-"$1/commands"} dir
  [[ -d "$source" ]] || return 0
  while IFS= read -r dir; do
    basename "$dir"
  done < <(find "$source" -mindepth 1 -maxdepth 1 -type d | sort)
}
