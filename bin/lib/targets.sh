#!/usr/bin/env bash

# Validate the artifact paths loaded from targets.conf before callers use them.
# Callers must set ROOT, CANONICAL_DEST, and TRANSFORMED_TARGETS first.
skill_x_validate_artifact_paths() {
  local paths=() labels=() entry adapter artifact path i j

  paths+=("$CANONICAL_DEST"); labels+=("CANONICAL_DEST")
  for entry in "${TRANSFORMED_TARGETS[@]}"; do
    [[ "$entry" == *:* && "$entry" != :* && "$entry" != *: ]] || {
      echo "Invalid transformed target entry '$entry': expected adapter:relative-artifact-path" >&2
      return 1
    }
    adapter=${entry%%:*}
    artifact=${entry#*:}
    [[ "$artifact" != *:* ]] || {
      echo "Invalid artifact path for $adapter: '$artifact'" >&2
      return 1
    }
    paths+=("$artifact"); labels+=("transformed target $adapter")
  done

  for i in "${!paths[@]}"; do
    path=${paths[$i]}
    [[ -n "$path" ]] || { echo "Invalid ${labels[$i]}: artifact path must not be empty" >&2; return 1; }
    [[ "$path" != /* ]] || { echo "Invalid ${labels[$i]} '$path': artifact path must be relative" >&2; return 1; }
    [[ "$path" != "." && "$path" != */. && "$path" != ./* && "$path" != *//* ]] || {
      echo "Invalid ${labels[$i]} '$path': artifact path must be a normalized child of the repository" >&2
      return 1
    }
    case "/$path/" in
      */../*|*/./*)
        echo "Invalid ${labels[$i]} '$path': '.' and '..' path components are not allowed" >&2
        return 1
        ;;
    esac
  done

  for i in "${!paths[@]}"; do
    for j in "${!paths[@]}"; do
      (( j > i )) || continue
      if [[ "${paths[$i]}" == "${paths[$j]}" ]]; then
        echo "Duplicate artifact destination '${paths[$i]}' (${labels[$i]} and ${labels[$j]})" >&2
        return 1
      fi
      if [[ "${paths[$i]}/" == "${paths[$j]}/"* || "${paths[$j]}/" == "${paths[$i]}/"* ]]; then
        echo "Overlapping artifact destinations '${paths[$i]}' and '${paths[$j]}' are not allowed" >&2
        return 1
      fi
    done
  done
}

# Custom destinations are local build configuration. Register them in the
# clone-local exclude file so disposable artifacts never enter normal status.
skill_x_ensure_artifacts_ignored() {
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0
  local git_dir exclude path entry pattern
  git_dir=$(git -C "$ROOT" rev-parse --git-dir)
  [[ "$git_dir" == /* ]] || git_dir="$ROOT/$git_dir"
  exclude="$git_dir/info/exclude"
  mkdir -p "$(dirname "$exclude")"
  touch "$exclude"
  for path in "$CANONICAL_DEST" "${TRANSFORMED_TARGETS[@]}"; do
    [[ "$path" == *:* ]] && path=${path#*:}
    pattern="/$path/"
    if ! git -C "$ROOT" check-ignore -q --no-index "$path/.skill-x-ignore-probe" 2>/dev/null; then
      printf '\n# skill-x disposable artifact\n%s\n' "$pattern" >> "$exclude"
    fi
    git -C "$ROOT" check-ignore -q --no-index "$path/.skill-x-ignore-probe" || {
      echo "Artifact destination '$path' is not ignored; refusing to build" >&2
      return 1
    }
  done
}
