# shellcheck shell=bash
# Shared primitives: paths, slugs, atomic writes, locking, template rendering.
#
# Every path this file resolves is project-local. Nothing is ever written to
# ~/.x-*, ~/.gstack or a shared /tmp: the whole runtime lives under .dev-hub/
# inside the repository so a Cycle can be inspected, committed or thrown away
# with ordinary Git commands.

x_die() { printf 'xdh: %s\n' "$*" >&2; exit 1; }
x_warn() { printf 'xdh: %s\n' "$*" >&2; }
x_emit() { printf '%s=%s\n' "$1" "$2"; }

# Emit a document as logical LF-terminated lines regardless of whether its
# physical line endings are LF, CRLF, or bare CR. This is a read-only view:
# writers still preserve the target document's original convention.
x_normalized_lines() {
  local file=$1
  [[ -f $file ]] || x_die "no such file: $file"
  LC_ALL=C awk '
    BEGIN { RS = "\034"; ORS = "" }
    {
      text = $0
      gsub(/\r\n/, "\n", text)
      gsub(/\r/, "\n", text)
      printf "%s", text
      if (text !~ /\n$/) printf "\n"
    }
  ' "$file"
}

# Lowercase ASCII, digits and single hyphens only, trimmed to 48 characters.
x_slugify() {
  local raw=$1 out
  out=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')
  while [[ $out == *--* ]]; do out=${out//--/-}; done
  out=${out#-}; out=${out%-}
  out=${out:0:48}
  out=${out%-}
  printf '%s' "$out"
}

x_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
x_stamp() { date -u +%Y%m%d-%H%M; }
x_stamp_seconds() { date -u +%Y%m%d-%H%M%S; }

# Resolve the *main* repository root even when invoked from a linked worktree.
# git rev-parse --git-common-dir points at the shared .git directory, which is
# what makes .dev-hub a single shared location rather than one copy per
# worktree. --path-format is only available on newer Git, hence the fallback.
x_resolve_paths() {
  if [[ -n ${X_MAIN_ROOT:-} ]]; then return 0; fi
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
    common=$(git rev-parse --git-common-dir 2>/dev/null) ||
    x_die "not inside a Git repository"
  [[ -d $common ]] || x_die "cannot resolve the shared Git directory"
  common=$(cd -- "$common" && pwd)

  local root
  root=$(dirname -- "$common")
  if [[ ! -d $root ]] || [[ $(basename -- "$common") != .git && ! -e $root/.git ]]; then
    root=$(git rev-parse --show-toplevel 2>/dev/null) || x_die "cannot resolve the repository root"
  fi

  X_MAIN_ROOT=$root
  X_DEV_HUB="$X_MAIN_ROOT/.dev-hub"
  X_ACTIVE="$X_DEV_HUB/active"
  X_WORKTREES="$X_DEV_HUB/worktrees"
  X_RUNTIME="$X_DEV_HUB/runtime"
  X_LOGS="$X_DEV_HUB/logs"
  X_CURRENT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$root")
  export X_MAIN_ROOT X_DEV_HUB X_ACTIVE X_WORKTREES X_RUNTIME X_LOGS X_CURRENT_ROOT
}

x_ensure_dev_hub() {
  x_resolve_paths
  mkdir -p "$X_ACTIVE" "$X_WORKTREES" "$X_RUNTIME" "$X_LOGS"
}

# .dev-hub/logs is the only tracked part of the hub; everything else is
# execution residue and must stay out of Git.
x_ensure_gitignore() {
  x_resolve_paths
  local file="$X_MAIN_ROOT/.gitignore" entry added=0
  local entries=(".dev-hub/active/" ".dev-hub/worktrees/" ".dev-hub/runtime/")
  local content=""
  if [[ -f $file ]]; then content=$(cat -- "$file"); fi
  for entry in "${entries[@]}"; do
    if ! printf '%s\n' "$content" | grep -Fxq -- "$entry"; then
      content=${content%$'\n'}
      if [[ -n $content ]]; then
        content="$content"$'\n'"$entry"
      else
        content=$entry
      fi
      added=1
    fi
  done
  if (( added )); then
    printf '%s\n' "$content" | x_atomic_write "$file"
  fi
  x_emit X_GITIGNORE_UPDATED "$added"
}

# Write stdin to $1 through a temporary file in the same directory, so a reader
# never observes a half-written Markdown document.
x_atomic_write() {
  local target=$1 dir tmp
  dir=$(dirname -- "$target")
  mkdir -p "$dir"
  tmp=$(mktemp "$dir/.xdh-write.XXXXXX")
  cat > "$tmp"
  chmod 644 "$tmp"
  mv -f "$tmp" "$target"
}

# mkdir-based mutex. flock is unavailable on macOS, and ID allocation only
# needs mutual exclusion between concurrent agents on one machine.
x_lock() {
  local lock=$1 waited=0
  mkdir -p "$(dirname -- "$lock")"
  until mkdir "$lock" 2>/dev/null; do
    waited=$(( waited + 1 ))
    if (( waited > 100 )); then
      # A lock older than two minutes belongs to a dead process.
      if [[ -d $lock ]] && [[ -z $(find "$lock" -maxdepth 0 -mmin -2 2>/dev/null) ]]; then
        rmdir "$lock" 2>/dev/null || true
        continue
      fi
      x_die "timed out waiting for lock: $lock"
    fi
    sleep 0.1 2>/dev/null || sleep 1
  done
  X_HELD_LOCK=$lock
  trap 'x_unlock' EXIT
}

x_unlock() {
  [[ -n ${X_HELD_LOCK:-} ]] || return 0
  rmdir "$X_HELD_LOCK" 2>/dev/null || true
  X_HELD_LOCK=
}

# render_template <file> KEY VALUE [KEY VALUE...] — literal {{KEY}} substitution
# with no shell or sed escaping hazards.
x_render_template() {
  local tpl=$1; shift
  [[ -f $tpl ]] || x_die "missing template: $tpl"
  local content
  content=$(cat -- "$tpl")
  while (( $# >= 2 )); do
    local key=$1 value=$2; shift 2
    content=${content//\{\{$key\}\}/$value}
  done
  printf '%s\n' "$content"
}

x_template() { printf '%s/%s.md' "$XDH_TEMPLATES" "$1"; }

# Read a `- Field: value` bullet from a Markdown header block.
x_field_get() {
  local file=$1 name=$2
  [[ -f $file ]] || x_die "no such file: $file"
  x_normalized_lines "$file" | awk -v name="$name" '
    $0 ~ "^- " name ":" {
      sub("^- " name ":[[:space:]]*", "")
      print
      exit
    }
  '
}

# Replace a `- Field: value` bullet in place, preserving every other byte.
x_field_set() {
  local file=$1 name=$2 value=$3 tmp
  [[ -f $file ]] || x_die "no such file: $file"
  # Staged next to the target, never in a shared /tmp: every byte this helper
  # writes has to stay inside the project, and awk's exit status has to be
  # known before anything replaces the original.
  tmp=$(mktemp "$(dirname -- "$file")/.xdh-field.XXXXXX")
  awk -v name="$name" -v value="$value" '
    BEGIN { done = 0 }
    { clean = $0; sub(/\r$/, "", clean); eol = ($0 ~ /\r$/ ? "\r" : "") }
    !done && clean ~ "^- " name ":" { print "- " name ": " value eol; done = 1; next }
    { print }
    END { if (!done) exit 9 }
  ' "$file" > "$tmp" || { rm -f "$tmp"; x_die "field not found in $file: $name"; }
  x_atomic_write "$file" < "$tmp"
  rm -f "$tmp"
}

# Default integration branch: origin/HEAD when the remote publishes it, then the
# conventional names. Never guessed silently — callers echo what was resolved.
x_base_branch() {
  local ref=""
  if ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s' "${ref#refs/remotes/origin/}"
    return 0
  fi
  local candidate
  for candidate in main master trunk; do
    if git show-ref --verify --quiet "refs/remotes/origin/$candidate" ||
       git show-ref --verify --quiet "refs/heads/$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf 'main'
}

x_base_ref() {
  local base=$1
  if git show-ref --verify --quiet "refs/remotes/origin/$base"; then
    printf 'origin/%s' "$base"
  elif git show-ref --verify --quiet "refs/heads/$base"; then
    printf '%s' "$base"
  else
    printf '%s' "$base"
  fi
}

# Join stdin lines with ", " (paste -sd', ' cycles its delimiter list, which
# silently produces "a,b c" for three or more entries).
x_join() {
  awk 'NF { if (n++) printf ", "; printf "%s", $0 } END { if (n) printf "\n" }'
}

x_require_value() {
  [[ -n ${2:-} ]] || x_die "missing required option: $1"
}

# Normalize a planning route into its canonical form: lowercase, comma-separated,
# no spaces, no duplicates, `engineering` present exactly once and last. Tokens
# product/design/devex may appear at most once each. Prints the canonical route
# or exits 1 with a clear message on invalid input.
x_route_normalize() {
  local raw=$1 token out="" IFS=','
  local c_product=0 c_design=0 c_devex=0 c_engineering=0
  local -a tokens
  read -r -a tokens <<< "$raw"
  for token in "${tokens[@]}"; do
    token=${token#"${token%%[![:space:]]*}"}
    token=${token%"${token##*[![:space:]]}"}
    [[ -n $token ]] || { printf 'xdh: route: empty token\n' >&2; return 1; }
    token=$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')
    case $token in
      product) c_product=$(( c_product + 1 )) ;;
      design) c_design=$(( c_design + 1 )) ;;
      devex) c_devex=$(( c_devex + 1 )) ;;
      engineering) c_engineering=$(( c_engineering + 1 )) ;;
      *) printf 'xdh: route: unknown facet "%s"\n' "$token" >&2; return 1 ;;
    esac
  done
  if (( c_engineering != 1 )); then
    printf 'xdh: route: engineering must appear exactly once\n' >&2
    return 1
  fi
  if (( c_product > 1 || c_design > 1 || c_devex > 1 )); then
    printf 'xdh: route: duplicate facet\n' >&2
    return 1
  fi
  (( c_product )) && out+="product,"
  (( c_design )) && out+="design,"
  (( c_devex )) && out+="devex,"
  out+="engineering"
  printf '%s' "$out"
}

# Print `pending` when the facet token is present in the canonical route, else
# `not-applicable`.
x_route_facet_status() {
  local route=$1 facet=$2 IFS=',' token
  local -a tokens
  read -r -a tokens <<< "$route"
  for token in "${tokens[@]}"; do
    [[ $token == "$facet" ]] && { printf 'pending'; return 0; }
  done
  printf 'not-applicable'
}

# Replace multiple `- Field: value` bullets in one awk pass and one atomic
# replacement. All named fields must exist, else nothing changes.
x_fields_set() {
  local file=$1; shift
  [[ -f $file ]] || x_die "no such file: $file"
  [[ $(( $# % 2 )) -eq 0 ]] || x_die "x_fields_set: name/value pairs required"
  local names="" values="" sep=$'\037'
  while (( $# )); do
    names="${names}${names:+$sep}$1"
    values="${values}${values:+$sep}$2"
    shift 2
  done
  local tmp
  tmp=$(mktemp "$(dirname -- "$file")/.xdh-field.XXXXXX")
  awk -v names="$names" -v values="$values" -v sep="$sep" '
    BEGIN { n = split(names, nm, sep); split(values, val, sep); for (i = 1; i <= n; i++) done[i] = 0 }
    { clean = $0; sub(/\r$/, "", clean); eol = ($0 ~ /\r$/ ? "\r" : "") }
    {
      for (i = 1; i <= n; i++) {
        if (!done[i] && clean ~ "^- " nm[i] ":") {
          print "- " nm[i] ": " val[i] eol
          done[i] = 1
          next
        }
      }
      print
    }
    END { for (i = 1; i <= n; i++) if (!done[i]) exit 9 }
  ' "$file" > "$tmp" || { rm -f "$tmp"; x_die "field not found in $file"; }
  x_atomic_write "$file" < "$tmp"
  rm -f "$tmp"
}

# Insert a block (multi-line string) immediately after the `- Field:` bullet.
# The block is staged to a file and read with getline: BSD awk rejects newlines
# inside a -v assignment.
x_insert_after_field() {
  local file=$1 field=$2 block=$3 tmp blockfile
  [[ -f $file ]] || x_die "no such file: $file"
  tmp=$(mktemp "$(dirname -- "$file")/.xdh-field.XXXXXX")
  blockfile=$(mktemp "$(dirname -- "$file")/.xdh-block.XXXXXX")
  printf '%s' "$block" > "$blockfile"
  awk -v field="$field" -v blockfile="$blockfile" '
    { sub(/\r$/, ""); print }
    !done && $0 ~ "^- " field ":" {
      while ((getline line < blockfile) > 0) print line
      close(blockfile)
      done = 1
    }
    END { if (!done) exit 9 }
  ' "$file" > "$tmp" || { rm -f "$tmp" "$blockfile"; x_die "field not found: $field"; }
  x_atomic_write "$file" < "$tmp"
  rm -f "$tmp" "$blockfile"
}

# Insert a block immediately before an exact `## Heading` line.
x_insert_before_heading() {
  local file=$1 heading=$2 block=$3 tmp blockfile
  [[ -f $file ]] || x_die "no such file: $file"
  tmp=$(mktemp "$(dirname -- "$file")/.xdh-field.XXXXXX")
  blockfile=$(mktemp "$(dirname -- "$file")/.xdh-block.XXXXXX")
  printf '%s' "$block" > "$blockfile"
  awk -v heading="$heading" -v blockfile="$blockfile" '
    { sub(/\r$/, "") }
    !done && $0 == heading {
      while ((getline line < blockfile) > 0) print line
      close(blockfile)
      done = 1
    }
    { print }
    END { if (!done) exit 9 }
  ' "$file" > "$tmp" || { rm -f "$tmp" "$blockfile"; x_die "heading not found: $heading"; }
  x_atomic_write "$file" < "$tmp"
  rm -f "$tmp" "$blockfile"
}
