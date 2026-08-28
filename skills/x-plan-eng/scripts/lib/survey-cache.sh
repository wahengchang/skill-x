# shellcheck shell=bash
# Project survey: the one-shot, machine-derivable snapshot of a repository that
# x-discovery and x-plan-eng read instead of scanning the tree themselves.
#
# The point is token cost, not convenience. Both skills used to walk README,
# entry points, schemas, configuration, tests and git log independently, so the
# same 100-300 KB landed in the agent's context twice. Everything here is a fact
# a script can produce, so the agent spends its context on judgement and on the
# few files it actually needs to read closely.
#
# The output is capped (X_SURVEY_MAX_BYTES). An uncapped survey would just move
# the cost from "scan the repo" to "read the survey", so every section is
# top-N bounded and the whole document is truncated as a last resort.

# Bump when the emitted sections or cache metadata change: the version is part
# of the cache key, so an upgraded xdh rebuilds a survey written by an older one.
X_SURVEY_SCHEMA=3
X_SURVEY_MAX_BYTES=8192

x_survey_dir() { x_resolve_paths; printf '%s' "$X_RUNTIME/survey"; }
x_survey_file() { printf '%s' "$(x_survey_dir)/survey.md"; }
x_survey_keyfile() { printf '%s' "$(x_survey_dir)/survey.key"; }
x_survey_graphfile() { printf '%s' "$(x_survey_dir)/survey.graph"; }

# SHA-256 of stdin. Mirrors lib/plan.sh's fallback chain rather than adding a
# second hashing path to the codebase.
x_survey_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    x_die "survey: sha256 unavailable"
  fi
}

# Digest the actual working content, not merely the porcelain status summary.
# `git status --porcelain` stays byte-for-byte identical while an already-dirty
# file is edited again, which used to make the cache incorrectly stay fresh.
#
# Tracked content is represented by the staged and unstaged binary diffs. Git
# does not include untracked files in either diff, so add their path + blob hash
# explicitly. The hub and CodeGraph index are execution residue and never part
# of the project snapshot; excluding both also prevents either tool from
# invalidating the survey by writing its own cache.
x_survey_worktree_digest() {
  x_resolve_paths
  {
    printf 'index\0'
    git -C "$X_MAIN_ROOT" diff --cached --no-ext-diff --binary -- \
      . ':(exclude).dev-hub/**' ':(exclude).codegraph/**' 2>/dev/null || true
    printf '\0worktree\0'
    git -C "$X_MAIN_ROOT" diff --no-ext-diff --binary -- \
      . ':(exclude).dev-hub/**' ':(exclude).codegraph/**' 2>/dev/null || true
    printf '\0untracked\0'
    local f
    while IFS= read -r -d '' f; do
      case $f in
        .dev-hub/*|.codegraph/*) continue ;;
      esac
      printf '%s\0' "$f"
      if [[ -L $X_MAIN_ROOT/$f ]]; then
        printf 'symlink\0%s\0' "$(readlink -- "$X_MAIN_ROOT/$f")"
      elif [[ -f $X_MAIN_ROOT/$f ]]; then
        git -C "$X_MAIN_ROOT" hash-object -- "$f" 2>/dev/null || printf 'unhashable'
        printf '\0'
      else
        printf 'missing\0'
      fi
    done < <(git -C "$X_MAIN_ROOT" ls-files -z --others --exclude-standard 2>/dev/null || true)
  } | x_survey_sha
}

# Cache key: commit + exact working content + schema version. A committed change
# moves HEAD; any staged, unstaged, or untracked content change moves the digest.
x_survey_key() {
  local head worktree
  x_resolve_paths
  head=$(git -C "$X_MAIN_ROOT" rev-parse HEAD 2>/dev/null || printf 'no-head')
  worktree=$(x_survey_worktree_digest)
  printf 'schema=%s\nhead=%s\nworktree=%s\n' "$X_SURVEY_SCHEMA" "$head" "$worktree"
}

# Tracked files plus untracked-but-not-ignored ones, NUL-separated. Always ask
# from the repository root: `git ls-files` invoked from a subdirectory otherwise
# returns only that subtree, which made the same repo produce different surveys
# depending on the caller's cwd.
x_survey_files() {
  x_resolve_paths
  {
    git -C "$X_MAIN_ROOT" ls-files -z --full-name 2>/dev/null || true
    git -C "$X_MAIN_ROOT" ls-files -z --full-name --others --exclude-standard 2>/dev/null || true
  } | LC_ALL=C sort -z -u | x_survey_exclude_runtime
}

# Drop generated runtime trees from the listing: the survey describes the
# project, never the hub's own state or the CodeGraph index.
x_survey_exclude_runtime() {
  local f
  while IFS= read -r -d '' f; do
    case $f in
      .dev-hub/*|.codegraph/*) ;;
      *) printf '%s\0' "$f" ;;
    esac
  done
}

# The subset of x_survey_files that `wc -l` can actually read. The repo tracks
# symlinks to directories (commands-src/*/scripts -> ../_x-shared/scripts), and
# wc exits non-zero on those; under `set -euo pipefail` that would abort the
# whole survey rather than skipping one path.
x_survey_regular_files() {
  local f
  while IFS= read -r -d '' f; do
    [[ -f $X_MAIN_ROOT/$f && ! -L $X_MAIN_ROOT/$f ]] && printf '%s\0' "$f"
  done < <(x_survey_files)
}

