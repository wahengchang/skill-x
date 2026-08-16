# shellcheck shell=bash
# Planning gate: deterministic input fingerprint, scoped facet writes, pure
# validation, and the two-phase check -> ready transition. This is a separate
# fingerprint from lib/review.sh: review fingerprints a whole Git tree, planning
# fingerprints a versioned serialization of the item's planning inputs.
#
# Output contract: BLOCKER diagnostics go to stderr, NOTICE observations go to
# stdout, X_* KEY=value records go to stdout via x_emit. This keeps blockers out
# of `$( ... )` command substitutions that capture the pure fingerprint value.

X_PLAN_FACETS=(product design devex engineering)

# Display-capitalized facet name for the item fields (DevEx keeps its camel case).
x_plan_facet_cap() {
  case $1 in
    product) printf Product ;;
    design) printf Design ;;
    devex) printf DevEx ;;
    engineering) printf Engineering ;;
    *) printf '%s' "$1" ;;
  esac
}

x_plan_blocker() { printf 'BLOCKER %s\n' "$*" >&2; }
x_plan_notice()  { printf 'NOTICE %s\n' "$*"; }

# Item id (IS-001, SP-002) from a filename like IS-001-slug.md.
x_plan_item_id() { basename -- "$1" | cut -d- -f1,2; }

# The directory whose ID/lock space a document belongs to: a Cycle's work-items/
# and work-groups/ resolve to the Cycle, everything else resolves to its parent.
x_plan_scope_for() {
  local parent
  parent=$(dirname -- "$1")
  case $(basename -- "$parent") in
    work-items|work-groups) dirname -- "$parent" ;;
    *) printf '%s' "$parent" ;;
  esac
}

x_plan_is_spike() { [[ $(x_plan_heading_count Method "$1") -eq 1 ]]; }

# Count of exact `## <heading>` occurrences.
x_plan_heading_count() {
  x_normalized_lines "$2" | LC_ALL=C awk -v h="## $1" '$0 == h { n++ } END { print n + 0 }'
}

x_plan_field_count() {
  x_normalized_lines "$2" | LC_ALL=C awk -v n="$1" '$0 ~ ("^- " n ":") { c++ } END { print c + 0 }'
}

# The raw normalized body of a level-2 section: CR stripped, trailing horizontal
# whitespace stripped, blank lines and order preserved. Exit 1 if the exact
# heading is absent (the caller enforces exactly-once cardinality separately).
x_plan_section_body() {
  local file=$1 heading=$2
  x_normalized_lines "$file" | LC_ALL=C awk -v h="## $heading" '
    $0 == h { inse = 1; next }
    inse && /^## / { exit }
    inse { sub(/[ \t]+$/, ""); print }
  '
}

# Normalized body -> one physical line (backslash doubled, then LF -> backslash+n).
# No trailing newline on output; the caller terminates the key line.
x_plan_encode() {
  local s=$1
  s="${s}"$'\n'
  s=${s//\\/\\\\}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

# Body of a section as an encoded single-line field value, requiring the heading
# to occur exactly once. Emits a BLOCKER (stderr) and exits 1 otherwise.
x_plan_body_field() {
  local file=$1 heading=$2 body count kebab
  count=$(x_plan_heading_count "$heading" "$file")
  if [[ $count -ne 1 ]]; then
    kebab=$(printf '%s' "$heading" | tr ' /' '--')
    x_plan_blocker "section=$kebab status=$([ $count -eq 0 ] && printf missing || printf duplicate)"
    return 1
  fi
  body=$(x_plan_section_body "$file" "$heading") || return 1
  x_plan_encode "$body"
}

# Validate, sort, and de-duplicate a comma/space-separated ID list. Rejects any
# token that is not WK-NNN / IS-NNN / SP-NNN.
x_plan_normalize_ids() {
  local raw=$1 id out="" seen=""
  for id in $(printf '%s' "$raw" | tr ',' ' '); do
    [[ -n $id ]] || continue
    if [[ ! $id =~ ^(WK|IS|SP)-[0-9]{3}$ ]]; then
      x_plan_blocker "selected-work=invalid id=$id"
      return 1
    fi
    if [[ " $seen " == *" $id "* ]]; then continue; fi
    seen="$seen $id"
    out="${out}${out:+,}$id"
  done
  printf '%s' "$out" | tr ',' '\n' | LC_ALL=C sort | paste -sd, -
}

# Exact byte SHA-256 of a file's contents. Unlike `$(cat file)`, this preserves
# trailing newlines, so two files differing only in trailing LF bytes hash
# differently. Prints 64 lowercase hex to stdout; prints a BLOCKER and returns
# non-zero when no SHA-256 tool is available.
x_plan_file_sha256() {
  local file=$1
  [[ -f $file ]] || { x_plan_blocker "item=missing file=$file"; return 1; }
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    x_plan_blocker "fingerprint=sha256-unavailable"
    return 1
  fi
}

# Pure SHA-256 over the exact versioned serialization. Prints the 64-hex
# fingerprint to stdout (nothing else); prints BLOCKER lines to stderr and
# returns non-zero on any input problem. The serialization ends in exactly one
# physical LF before hashing.
x_plan_compute_fingerprint() {
  local file=$1
  [[ -f $file ]] || { x_plan_blocker "item=missing file=$file"; return 1; }
  export LC_ALL=C

  local format route sw canon
  if x_plan_is_spike "$file"; then
    format=x-plan-input-spike-v1
  else
    format=x-plan-input-v1
  fi

  route=$(x_field_get "$file" "Planning route")
  if [[ -z $route ]]; then
    x_plan_blocker "section=Planning-route status=missing"
    return 1
  fi
  # The fingerprint requires the stored route to already be canonical: it never
  # silently normalizes a non-canonical route, which would hide a schema error.
  canon=$(x_route_normalize "$route") || { x_plan_blocker "route status=non-canonical"; return 1; }
  [[ $canon == "$route" ]] || { x_plan_blocker "route status=non-canonical"; return 1; }
  route=$canon

  # A Spike always uses exactly `engineering`.
  if [[ $format == x-plan-input-spike-v1 && $route != engineering ]]; then
    x_plan_blocker "route status=spike-requires-engineering"
    return 1
  fi

  sw=$(x_field_get "$file" "Selected work")
  sw=$(x_plan_normalize_ids "${sw:--}") || return 1

  local serial
  if [[ $format == x-plan-input-spike-v1 ]]; then
    local cq st mt dr
    cq=$(x_plan_body_field "$file" "Core Question") || return 1
    st=$(x_plan_body_field "$file" "Scope / Timebox") || return 1
    mt=$(x_plan_body_field "$file" "Method") || return 1
    dr=$(x_plan_body_field "$file" "Decision Rule") || return 1
    serial=$(printf 'format=x-plan-input-spike-v1\nroute=%s\nselected-work=%s\nproblem-goal=%s\nscope=%s\nmethod=%s\ndecision-rule=%s' \
      "$route" "$sw" "$cq" "$st" "$mt" "$dr")
  else
    local pg sc cd
    pg=$(x_plan_body_field "$file" "Problem / Goal") || return 1
    sc=$(x_plan_body_field "$file" "Scope") || return 1
    cd=$(x_plan_body_field "$file" "Current → Desired Behavior") || return 1
    serial=$(printf 'format=x-plan-input-v1\nroute=%s\nselected-work=%s\nproblem-goal=%s\nscope=%s\ncurrent-desired=%s' \
      "$route" "$sw" "$pg" "$sc" "$cd")
  fi

  local fp
  if command -v sha256sum >/dev/null 2>&1; then
    fp=$(printf '%s\n' "$serial" | sha256sum | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    fp=$(printf '%s\n' "$serial" | shasum -a 256 | awk '{print $1}')
  else
    x_plan_blocker "fingerprint=sha256-unavailable"
    return 1
  fi
  printf '%s' "$fp"
}

# Public command: emit format + fingerprint.
x_plan_fingerprint() {
  local file=$1
  [[ -f $file ]] || x_die "no such file: $file"
  local format fp
  if x_plan_is_spike "$file"; then format=x-plan-input-spike-v1; else format=x-plan-input-v1; fi
  fp=$(x_plan_compute_fingerprint "$file") || return 1
  x_emit X_PLAN_FORMAT "$format"
  x_emit X_PLAN_FINGERPRINT "$fp"
}

# True when the section has at least one line of non-placeholder content.
x_plan_has_content() {
  local file=$1 heading=$2
  [[ $(x_plan_heading_count "$heading" "$file") -eq 1 ]] || return 1
  x_normalized_lines "$file" | LC_ALL=C awk -v h="## $heading" '
    $0 == h { inse = 1; next }
    inse && /^## / { exit }
    inse {
      sub(/\r$/, "")
      line = $0
      sub(/[ \t]+$/, "", line)
      if (line == "") next
      if (line ~ /^<[^>]+>$/) next
      # `#+` rather than `#{1,6}`: mawk 1.3.4 aborts with a REcompile() panic on
      # an interval followed by an alternation group, which would make every
      # section look empty and every `plan check` fail on a mawk host.
      if (line ~ /^#+([ \t]|$)/) next
      if (line ~ /^\x60\x60\x60/ || line ~ /^~~~/) next
      if (line ~ /^\|/) next
      if (line ~ /^[-*_][-* _]*$/) next
      if (line == "1.") next
      if (line ~ /^- \[ \]$/) next
      if (line ~ /^- \[x\]$|^- \[X\]$/) next
      if (line ~ /^\|[-: |]+\|/) next
      if (line == "- Code/docs to inspect:" || line == "- Experiment/prototype:" || line == "- Evidence to collect:") next
      if (line == "- Conclusion:" || line == "- Evidence:" || line == "- Follow-up Issue(s):") next
      if (line ~ /^`Do this:/) next
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  '
}

# Owner Decisions rows as tagged TSV. Every data row must have exactly six
# cells; malformed rows are emitted as invalid so the caller fails closed.
x_plan_owner_decisions() {
  x_normalized_lines "$1" | LC_ALL=C awk -F'|' '
    /^## / { inse = ($0 == "## Owner Decisions") }
    inse && /^\|/ {
      for (i = 2; i <= 7; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
      if ($2 == "ID") {
        if (NF != 8 || $3 != "Facet" || $4 != "Question / change" || $5 != "Decision" || $6 != "State" || $7 != "Fingerprint")
          print "invalid\theader"
        next
      }
      if ($0 ~ /^\|[-: |]+\|/) {
        if (NF != 8) print "invalid\tseparator"
        next
      }
      if (NF != 8 || $1 !~ /^[ \t]*$/ || $8 !~ /^[ \t]*$/) {
        print "invalid\t" ($2 == "" ? "unknown" : $2)
        next
      }
      print "valid\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7
    }
  '
}

x_plan_scope_complete() {
  local file=$1
  x_normalized_lines "$file" | LC_ALL=C awk '
    /^## Scope$/ { in_scope = 1; next }
    in_scope && /^## / { exit }
    in_scope && /^### In$/ { part = "in"; seen_in = 1; next }
    in_scope && /^### Out$/ { part = "out"; seen_out = 1; next }
    in_scope {
      line = $0
      sub(/[ \t]+$/, "", line)
      # `#+` rather than `#{1,6}` for the same mawk REcompile() reason as above.
      if (line == "" || line ~ /^#+([ \t]|$)/ || line ~ /^\x60\x60\x60/ || line ~ /^~~~/ ||
          line ~ /^\|/ || line ~ /^<[^>]+>$/ || line == "-" || line == "—") next
      if (part == "in") content_in = 1
      if (part == "out") content_out = 1
    }
    END { if (!(seen_in && seen_out && content_in && content_out)) exit 1 }
  '
}

x_plan_is_placeholder() {
  local value=$1 lower
  value=$(printf '%s' "$value" | awk '{$1=$1; print}')
  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  case $lower in
    ""|-|—|todo|tbd|placeholder|"<decision>"|"<question>"|"<question / change>"|"<recommendation>"|"<answer>") return 0 ;;
  esac
  [[ $lower == \<*\> ]]
}

# Pure validator: prints BLOCKER lines (stderr) and NOTICE lines (stdout) and
# returns non-zero if the item cannot pass the planning gate. Never writes and
# never locks.
x_plan_validate() {
  local file=$1 blockers=0
  [[ -f $file ]] || { x_plan_blocker "item=missing file=$file"; return 1; }

  local fp route canon
  route=$(x_field_get "$file" "Planning route")
  if [[ -z $route ]]; then
    x_plan_blocker "section=Planning-route status=missing"
    return 1
  fi
  canon=$(x_route_normalize "$route") || { x_plan_blocker "route status=non-canonical"; return 1; }
  [[ $canon == "$route" ]] || { x_plan_blocker "route status=non-canonical"; return 1; }
  if x_plan_is_spike "$file" && [[ $canon != engineering ]]; then
    x_plan_blocker "route status=spike-requires-engineering"
    return 1
  fi

  fp=$(x_plan_compute_fingerprint "$file") || return 1

  local product_selected=0
  [[ " ${canon//,/ } " == *" product "* ]] && product_selected=1

  # Parse Owner Decisions first so deferrals can be checked against accepted rows.
  local accepted_facets=""
  if [[ $(x_plan_heading_count 'Owner Decisions' "$file") -ne 1 ]]; then
    x_plan_blocker "section=Owner-Decisions status=missing"
    blockers=$(( blockers + 1 ))
  else
    local od_tag od_id od_facet od_question od_decision od_state od_fingerprint od_fp seen=""
    while IFS=$'\t' read -r od_tag od_id od_facet od_question od_decision od_state od_fingerprint; do
      if [[ $od_tag != valid ]]; then
        x_plan_blocker "decision=${od_id:-unknown} status=invalid-schema"; blockers=$(( blockers + 1 )); continue
      fi
      [[ -n $od_id ]] || continue
      if [[ ! $od_id =~ ^OD-[0-9]{3}$ || ! " ${X_PLAN_FACETS[*]} " == *" $od_facet "* ]] ||
         x_plan_is_placeholder "$od_question" || x_plan_is_placeholder "$od_decision" ||
         [[ " $seen " == *" $od_id "* ]]; then
        x_plan_blocker "decision=${od_id:-unknown} status=invalid"; blockers=$(( blockers + 1 )); continue
      fi
      seen="$seen $od_id"
      case $od_state in
        pending)
          x_plan_blocker "decision=$od_id state=pending"
          blockers=$(( blockers + 1 ))
          ;;
        accepted@*)
          od_fp=${od_state#accepted@}
          if [[ $od_fp == "$fp" && $od_fingerprint == "$fp" ]]; then
            accepted_facets="$accepted_facets $od_facet"
          else
            x_plan_notice "decision=$od_id state=accepted@$od_fp"
            if [[ $product_selected -eq 1 && $od_facet == product ]]; then
              x_plan_blocker "decision=$od_id state=stale-product re-anchor-required"
              blockers=$(( blockers + 1 ))
            fi
          fi
          ;;
        *) x_plan_blocker "decision=$od_id state=invalid"; blockers=$(( blockers + 1 )) ;;
      esac
    done < <(x_plan_owner_decisions "$file")
  fi

  # Facet states.
  local facet cap status
  for facet in "${X_PLAN_FACETS[@]}"; do
    cap=$(x_plan_facet_cap "$facet")
    status=$(x_field_get "$file" "$cap facet")
    if [[ " ${canon//,/ } " == *" $facet "* ]]; then
      if [[ $facet == engineering ]]; then
        if [[ $status != "completed@$fp" ]]; then
          if [[ $status == *"@"* ]]; then
            x_plan_blocker "facet=$facet status=stale expected=$fp actual=$status"
          else
            x_plan_blocker "facet=$facet status=${status:-missing}"
          fi
          blockers=$(( blockers + 1 ))
        fi
      else
        case $status in
          "completed@$fp") ;;
          "deferred-owner@$fp"|"deferred-missing@$fp")
            [[ " $accepted_facets " == *" $facet "* ]] || {
              x_plan_blocker "facet=$facet status=deferred-unaccepted"
              blockers=$(( blockers + 1 ))
            } ;;
          *"@"*) x_plan_blocker "facet=$facet status=stale expected=$fp actual=$status"; blockers=$(( blockers + 1 )) ;;
          *) x_plan_blocker "facet=$facet status=${status:-missing}"; blockers=$(( blockers + 1 )) ;;
        esac
      fi
    else
      if [[ $status != not-applicable ]]; then
        x_plan_blocker "facet=$facet status=${status:-missing} expected=not-applicable"
        blockers=$(( blockers + 1 ))
      fi
    fi
  done

  for facet in "${X_PLAN_FACETS[@]}"; do
    cap=$(x_plan_facet_cap "$facet")
    status=$(x_field_get "$file" "$cap facet")
    if [[ " ${canon//,/ } " == *" $facet "* ]] && [[ $status == completed@* ]] && ! x_plan_has_content "$file" "$cap Facet"; then
      x_plan_blocker "section=$cap-Facet status=empty"; blockers=$(( blockers + 1 ))
    fi
  done

  # Scaffold presence for every selected facet.
  for facet in "${X_PLAN_FACETS[@]}"; do
    cap=$(x_plan_facet_cap "$facet")
    if [[ " ${canon//,/ } " == *" $facet "* ]]; then
      if [[ $(x_plan_heading_count "$cap Facet" "$file") -ne 1 ]]; then
        x_plan_blocker "section=$cap-Facet status=missing"
        blockers=$(( blockers + 1 ))
      fi
    fi
  done

  # Section content + completeness (issue vs spike).
  if x_plan_is_spike "$file"; then
    local req
    for req in 'Core Question' 'Why This Blocks a Decision' 'Scope / Timebox' 'Method' 'Decision Rule' 'Required Output' 'Constraints'; do
      if ! x_plan_has_content "$file" "$req"; then
        x_plan_blocker "section=$(printf '%s' "$req" | tr ' /' '--') status=empty"
        blockers=$(( blockers + 1 ))
      fi
    done
  else
    local sec
    for sec in 'Problem / Goal' 'Current → Desired Behavior' 'Architecture / Data Flow' 'Interfaces / Dependencies' 'Failure Modes / Edge Cases / Risks' 'Implementation Order' 'Acceptance Criteria'; do
      if ! x_plan_has_content "$file" "$sec"; then
        x_plan_blocker "section=$(printf '%s' "$sec" | tr ' /' '--') status=empty"
        blockers=$(( blockers + 1 ))
      fi
    done
    if ! x_plan_scope_complete "$file"; then
      x_plan_blocker "section=Scope status=missing-in-or-out"
      blockers=$(( blockers + 1 ))
    fi
    if ! x_normalized_lines "$file" | LC_ALL=C awk '/^## Implementation Order$/{f=1;next} /^## /{f=0} f && /^[0-9]+\. .+/{ok=1} END{if(!ok) exit 1}'; then
      x_plan_blocker "section=Implementation-Order status=no-numbered-step"
      blockers=$(( blockers + 1 ))
    fi
    if ! x_normalized_lines "$file" | LC_ALL=C awk -F'|' '
      /^## Tests$/ { f=1; next }
      /^## / { f=0 }
      f && /^\|/ && $0 !~ /^\|[-: |]+\|/ {
        cell=$2; gsub(/^[ \t]+|[ \t]+$/, "", cell)
        if (cell != "" && cell != "Layer") ok=1
      }
      END { if (!ok) exit 1 }
    '; then
      x_plan_blocker "section=Tests status=no-row"
      blockers=$(( blockers + 1 ))
    fi
    if ! x_normalized_lines "$file" | LC_ALL=C awk '/^## Acceptance Criteria$/{f=1;next} /^## /{f=0} f && (/^[0-9]+\./ || /^- \[[xX]\]/){ok=1} END{if(!ok) exit 1}'; then
      x_plan_blocker "section=Acceptance-Criteria status=no-check"
      blockers=$(( blockers + 1 ))
    fi
  fi

  # Definition of Ready: every box except the execution-environment item must be
  # checked before the first plan check.
  local dor
  dor=$(x_normalized_lines "$file" | LC_ALL=C awk '
    /^## / { inse = ($0 == "## Definition of Ready") }
    inse && /^- \[ \]/ {
      if ($0 !~ /Owner\/WG\/branch\/worktree/) print
    }
  ')
  if [[ -n $dor ]]; then
    while IFS= read -r line; do
      x_plan_blocker "dor=unchecked line=$line"
      blockers=$(( blockers + 1 ))
    done <<< "$dor"
  fi

  (( blockers == 0 ))
}

# Reject a generic `field set ... Status ready` on a new-format item.
x_plan_guard_ready() {
  local file=$1 name=$2 value=$3 v
  [[ $name == Status ]] || return 0
  v=${value#"${value%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  v=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
  [[ $v == ready ]] || return 0
  if [[ $(x_plan_field_count "Planning route" "$file") -gt 0 ]]; then
    printf 'xdh: new-format item: use "xdh plan ready <item>" instead of "field set ... Status ready"\n' >&2
    exit 1
  fi
}

# Idempotent in-place upgrade of a legacy draft to the new-format schema. Insert
# the header after `Created` and only the missing H2 scaffolds before Handover.
x_plan_init() {
  local file="" route="" selected_work=""
  while (( $# )); do
    case $1 in
      --route) route=$2; shift 2 ;;
      --selected-work) selected_work=$2; shift 2 ;;
      *) file=$1; shift ;;
    esac
  done
  x_require_value --route "$route"
  x_require_value --selected-work "$selected_work"
  [[ -n $file && -f $file ]] || x_die "plan init: missing item file"
  file=$(x_plan_mutable_target "$file" "plan init")

  local id
  id=$(x_plan_item_id "$file")

  # Schema preflight runs even on an already-initialized item: a duplicate
  # required heading is a corrupt schema and must be rejected, never silently
  # "reused".
  local required=('Owner Decisions' 'Product Facet' 'Design Facet' 'DevEx Facet' 'Engineering Facet')
  if x_plan_is_spike "$file"; then required+=('Constraints'); fi
  local heading missing="" count
  for heading in "${required[@]}"; do
    count=$(x_plan_heading_count "$heading" "$file")
    case $count in
      0) ;;
      1) ;;
      *) x_die "plan init: duplicate required heading '## $heading'"; ;;
    esac
    if [[ $count -eq 0 ]]; then
      missing="${missing}${missing:+ }$heading"
    fi
  done

  if [[ -n $(x_field_get "$file" "Planning route") ]]; then
    # Already initialized: reuse is a no-op only when the schema is intact. A
    # missing required scaffold or a wrong Handover cardinality is a corrupt
    # schema and is rejected byte-identically, never silently "reused".
    [[ -z $missing ]] || x_die "plan init: missing required heading(s): $missing"
    [[ $(x_plan_heading_count 'Handover' "$file") -eq 1 ]] || x_die "plan init: exactly one ## Handover required"
    x_emit X_PLAN_INITIALIZED "$id"
    x_emit X_PLAN_REUSED yes
    return 0
  fi

  local status
  status=$(x_field_get "$file" Status)
  [[ $status == draft ]] || x_die "plan init: item is not a draft (status=$status)"

  [[ $(x_plan_heading_count 'Handover' "$file") -eq 1 ]] || x_die "plan init: exactly one ## Handover required"

  local norm_route pf df vf ef
  norm_route=$(x_route_normalize "$route") || x_die "plan init: invalid --route '$route'"
  pf=$(x_route_facet_status "$norm_route" product)
  df=$(x_route_facet_status "$norm_route" design)
  vf=$(x_route_facet_status "$norm_route" devex)
  ef=$(x_route_facet_status "$norm_route" engineering)

  local header
  header="- Planning route: $norm_route
- Selected work: $selected_work
- Planning input fingerprint: —
- Product facet: $pf
- Product evidence: —
- Design facet: $df
- Design evidence: —
- DevEx facet: $vf
- DevEx evidence: —
- Engineering facet: $ef
- Engineering evidence: —
- Planning Complete: pending
- Execution Ready: pending
"

  # Insert only the missing scaffolds, in canonical order, before Handover.
  local scaffolds="" h
  for h in 'Owner Decisions' 'Product Facet' 'Design Facet' 'DevEx Facet' 'Engineering Facet'; do
    [[ " $missing " == *" $h "* ]] || continue
    if [[ $h == 'Owner Decisions' ]]; then
      scaffolds="${scaffolds}## Owner Decisions

| ID | Facet | Question / change | Decision | State | Fingerprint |
|---|---|---|---|---|---|

"
    else
      scaffolds="${scaffolds}## $h

"
    fi
  done
  if [[ " $missing " == *" Constraints "* ]]; then
    scaffolds="${scaffolds}## Constraints

"
  fi

  x_plan_init_rewrite "$file" "$header" "$scaffolds"

  x_emit X_PLAN_INITIALIZED "$id"
  x_emit X_PLAN_REUSED no
}

# Single-pass, atomic upgrade: insert the header after `Created` and the missing
# scaffolds immediately before `## Handover`, preserving every other byte.
x_plan_init_rewrite() {
  local file=$1 header=$2 scaffolds=$3 tmp hfile sfile
  tmp=$(mktemp "$(dirname -- "$file")/.xdh-field.XXXXXX")
  hfile=$(mktemp "$(dirname -- "$file")/.xdh-block.XXXXXX")
  sfile=$(mktemp "$(dirname -- "$file")/.xdh-block.XXXXXX")
  printf '%s' "$header" > "$hfile"
  printf '%s' "$scaffolds" > "$sfile"
  awk -v hfile="$hfile" -v sfile="$sfile" '
    { clean = $0; sub(/\r$/, "", clean); if (!seen) { eol = ($0 ~ /\r$/ ? "\r" : ""); seen = 1 } }
    !sdone && clean == "## Handover" {
      while ((getline line < sfile) > 0) print line eol
      close(sfile)
      sdone = 1
    }
    { print }
    !hdone && clean ~ "^- Created:" {
      while ((getline line < hfile) > 0) print line eol
      close(hfile)
      hdone = 1
    }
    END { if (!hdone || !sdone) exit 9 }
  ' "$file" > "$tmp" || { rm -f "$tmp" "$hfile" "$sfile"; x_die "plan init: missing Created or ## Handover"; }
  x_atomic_write "$file" < "$tmp"
  rm -f "$tmp" "$hfile" "$sfile"
}

# Resolve a project path canonically (symlinks and `..` dereferenced).
x_plan_realpath() {
  local p=$1
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p" 2>/dev/null
    return $?
  fi
  # No `realpath` available: canonicalize the directory with `pwd -P`, then
  # chase a chain of symlinks in the basename. Relative symlink targets are
  # joined with the symlink's own directory and re-canonicalized, so a link
  # such as `../outside` or `../../escape` cannot slip through as a lexical
  # path that merely *looks* contained.
  local dir base link
  dir=$(cd -- "$(dirname -- "$p")" 2>/dev/null && pwd -P) || return 1
  base=$(basename -- "$p")
  while [[ -L "$dir/$base" ]]; do
    link=$(readlink -- "$dir/$base") || return 1
    if [[ $link == /* ]]; then
      dir=$(cd -- "$(dirname -- "$link")" 2>/dev/null && pwd -P) || return 1
      base=$(basename -- "$link")
    else
      dir=$(cd -- "$dir/$(dirname -- "$link")" 2>/dev/null && pwd -P) || return 1
      base=$(basename -- "$link")
    fi
  done
  dir=$(cd -- "$dir" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s' "$dir" "$base"
}

# Every planning mutation is confined to the repository's canonical .dev-hub
# tree. Canonicalizing both sides rejects lexical traversal and symlink escapes
# before a lock or temporary file can be created.
x_plan_mutable_target() {
  local file=$1 operation=$2 target hub repo
  repo=$(git -C "$(dirname -- "$file")" rev-parse --show-toplevel 2>/dev/null) ||
    x_die "$operation: item is not inside a Git repository"
  target=$(x_plan_realpath "$file") || x_die "$operation: invalid item path"
  hub=$(x_plan_realpath "$repo/.dev-hub") || x_die "$operation: cannot resolve .dev-hub"
  [[ -f $target && $target == "$hub"/* ]] || x_die "$operation: item outside .dev-hub"
  printf '%s' "$target"
}

# The sole Facet-mode writer: one facet's status/evidence fields (and optionally
# its H2 section body) applied in one staged document and one atomic replacement
# under one scope lock.
x_plan_facet_set() {
  local file="" facet="" status="" evidence="" section_file="" owner_decision_file=""
  while (( $# )); do
    case $1 in
      --facet) facet=$2; shift 2 ;;
      --status) status=$2; shift 2 ;;
      --evidence) evidence=$2; shift 2 ;;
      --section-file) section_file=$2; shift 2 ;;
      --owner-decision-file) owner_decision_file=$2; shift 2 ;;
      *) file=$1; shift ;;
    esac
  done
  x_require_value --facet "$facet"
  x_require_value --status "$status"
  x_require_value --evidence "$evidence"
  [[ -n $file && -f $file ]] || x_die "plan facet set: missing item file"
  file=$(x_plan_mutable_target "$file" "plan facet set")

  case " ${X_PLAN_FACETS[*]} " in
    *" $facet "*) ;;
    *) x_plan_blocker "facet=$facet status=unknown"; return 1 ;;
  esac

  # Evidence is a single-line, non-placeholder reference.
  if [[ $evidence == *$'\n'* || $evidence == — || $evidence == - ]]; then
    x_plan_blocker "facet=$facet status=evidence-invalid"
    return 1
  fi

  local scope lock
  scope=$(x_plan_scope_for "$file")
  lock="$scope/.xdh-plan.lock"
  x_lock "$lock"
  if ! x_plan_facet_set_locked "$file" "$facet" "$status" "$evidence" "$section_file" "$owner_decision_file"; then
    x_unlock
    return 1
  fi
  x_unlock

  x_emit X_PLAN_FACET_SET "$facet"
}

x_plan_facet_set_locked() {
  local file=$1 facet=$2 status=$3 evidence=$4 section_file=$5 owner_decision_file=$6
  local route canon
  route=$(x_field_get "$file" "Planning route")
  [[ -n $route ]] || { x_plan_blocker "section=Planning-route status=missing"; return 1; }
  canon=$(x_route_normalize "$route") || { x_plan_blocker "route status=non-canonical"; return 1; }
  [[ $canon == "$route" ]] || { x_plan_blocker "route status=non-canonical"; return 1; }
  [[ " ${canon//,/ } " == *" $facet "* ]] || { x_plan_blocker "facet=$facet status=not-in-route"; return 1; }

  local fp
  fp=$(x_plan_compute_fingerprint "$file") || return 1

  # Engineering is mandatory and can never be deferred or marked not-applicable.
  if [[ $facet == engineering ]]; then
    case $status in
      deferred-owner@*|deferred-missing@*)
        x_plan_blocker "facet=engineering status=deferral-forbidden value=$status"; return 1 ;;
      not-applicable)
        x_plan_blocker "facet=engineering status=not-applicable-forbidden"; return 1 ;;
    esac
  fi

  case $status in
    pending|in-progress|blocked) ;;
    completed@*|deferred-owner@*|deferred-missing@*)
      [[ $status == *"@$fp" ]] || { x_plan_blocker "facet=$facet status=stale expected=$fp actual=$status"; return 1; }
      ;;
    *) x_plan_blocker "facet=$facet status=invalid value=$status"; return 1 ;;
  esac

  local cap
  cap=$(x_plan_facet_cap "$facet")

  # The target H2 must occur exactly once.
  if [[ $(x_plan_heading_count "$cap Facet" "$file") -ne 1 ]]; then
    x_plan_blocker "facet=$facet status=section-cardinality"
    return 1
  fi

  local section_content=""
  if [[ -n $section_file ]]; then
    [[ -f $section_file ]] || { x_plan_blocker "facet=$facet status=section-file-missing"; return 1; }
    x_resolve_paths
    local sec_real
    sec_real=$(x_plan_realpath "$section_file") || { x_plan_blocker "facet=$facet status=section-file-outside-project"; return 1; }
    [[ $sec_real == "$X_MAIN_ROOT"/* ]] || { x_plan_blocker "facet=$facet status=section-file-outside-project"; return 1; }
    section_content=$(cat -- "$sec_real")
  fi
  # A completed facet must leave substantive evidence in its own section. When
  # callers have no longer brief, its required single-line evidence is retained
  # there rather than allowing an empty completed scaffold.
  if [[ $status == completed@* && -z $section_content ]]; then
    section_content=$evidence
  fi

  local decision_row=""
  if [[ -n $owner_decision_file ]]; then
    [[ $facet == product && $status == blocked && -f $owner_decision_file ]] || { x_plan_blocker "facet=$facet status=owner-decision-invalid"; return 1; }
    x_resolve_paths
    local decision_real
    decision_real=$(x_plan_realpath "$owner_decision_file") || { x_plan_blocker "facet=$facet status=owner-decision-outside-project"; return 1; }
    [[ $decision_real == "$X_MAIN_ROOT"/* ]] || { x_plan_blocker "facet=$facet status=owner-decision-outside-project"; return 1; }
    decision_row=$(cat -- "$decision_real")
    [[ $decision_row != *$'\n'* ]] || { x_plan_blocker "facet=product status=owner-decision-invalid"; return 1; }
    if [[ ! $decision_row =~ ^\|[[:space:]]*OD-[0-9]{3}[[:space:]]*\|[[:space:]]*product[[:space:]]*\|[[:space:]]*[^\|]+[[:space:]]*\|[[:space:]]*[^\|]+[[:space:]]*\|[[:space:]]*pending[[:space:]]*\|[[:space:]]*—[[:space:]]*\|$ ]]; then
      x_plan_blocker "facet=product status=owner-decision-invalid"
      return 1
    fi
    local did dfacet dquestion ddecision dstate dfingerprint existing_tag existing_id existing_facet existing_question existing_decision existing_state existing_fingerprint
    IFS=$'\t' read -r did dfacet dquestion ddecision dstate dfingerprint < <(
      printf '%s\n' "$decision_row" | awk -F'|' '{
        for (i=2; i<=7; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
        print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7
      }'
    )
    if x_plan_is_placeholder "$dquestion" || x_plan_is_placeholder "$ddecision"; then
      x_plan_blocker "facet=product status=owner-decision-invalid"
      return 1
    fi
    while IFS=$'\t' read -r existing_tag existing_id existing_facet existing_question existing_decision existing_state existing_fingerprint; do
      if [[ $existing_tag != valid ]]; then
        x_plan_blocker "decision=${existing_id:-unknown} status=invalid-schema"
        return 1
      fi
      [[ $existing_tag == valid && $existing_id == "$did" ]] || continue
      if [[ $existing_facet == "$dfacet" && $existing_question == "$dquestion" &&
            $existing_decision == "$ddecision" && $existing_state == "$dstate" &&
            $existing_fingerprint == "$dfingerprint" ]]; then
        decision_row=""
      else
        x_plan_blocker "decision=$did status=id-collision"
        return 1
      fi
    done < <(x_plan_owner_decisions "$file")
  fi

  x_plan_facet_write "$file" "$cap" "$status" "$evidence" "$section_content" "$decision_row"
  x_emit X_PLAN_FINGERPRINT "$fp"
}

# One staged document + one atomic replacement: set the facet status and
# evidence fields, and (when body is non-empty) replace the facet's H2 body.
x_plan_facet_write() {
  local file=$1 cap=$2 status=$3 evidence=$4 body=$5 decision=$6 tmp bodyfile=""
  tmp=$(mktemp "$(dirname -- "$file")/.xdh-field.XXXXXX")
  if [[ -n $body ]]; then
    bodyfile=$(mktemp "$(dirname -- "$file")/.xdh-body.XXXXXX")
    printf '%s' "$body" > "$bodyfile"
  fi
  awk -v cap="$cap" -v status="$status" -v evidence="$evidence" -v bodyfile="$bodyfile" -v decision="$decision" '
    BEGIN { sf = cap " facet"; ev = cap " evidence"; h2 = "## " cap " Facet"; sdone = 0; edone = 0; insec = 0 }
    { clean = $0; sub(/\r$/, "", clean); eol = ($0 ~ /\r$/ ? "\r" : "") }
    !sdone && clean ~ ("^- " sf ":") { print "- " sf ": " status eol; sdone = 1; next }
    !edone && clean ~ ("^- " ev ":") { print "- " ev ": " evidence eol; edone = 1; next }
    clean == "## Owner Decisions" && decision != "" { print; in_decisions = 1; next }
    in_decisions && clean ~ /^\|[-: |]+\|/ { print; print decision eol; in_decisions = 0; next }
    clean == h2 {
      print
      if (bodyfile != "") {
        insec = 1
        while ((getline line < bodyfile) > 0) print line eol
        close(bodyfile)
      }
      next
    }
    insec && clean ~ /^## / { insec = 0; print; next }
    insec { next }
    { print }
    END { if (!sdone || !edone || (decision != "" && in_decisions)) exit 9 }
  ' "$file" > "$tmp" || { rm -f "$tmp" "$bodyfile"; x_die "plan facet set: field not found"; }
  x_atomic_write "$file" < "$tmp"
  rm -f "$tmp" "$bodyfile"
}

# ID-keyed Owner Decision upsert. New decisions start pending; the only allowed
# transition is pending -> accepted@<current planning fingerprint>. Identical
# retries are no-ops and every other ID collision fails without changing bytes.
x_plan_decision_set() {
  local file="" id="" facet="" question="" decision="" state=""
  while (( $# )); do
    case $1 in
      --id) id=$2; shift 2 ;;
      --facet) facet=$2; shift 2 ;;
      --question) question=$2; shift 2 ;;
      --decision) decision=$2; shift 2 ;;
      --state) state=$2; shift 2 ;;
      --*) x_die "plan decision set: unknown option $1" ;;
      *) [[ -z $file ]] || x_die "plan decision set: multiple item files"; file=$1; shift ;;
    esac
  done
  [[ -n $file && -f $file ]] || x_die "plan decision set: missing item file"
  file=$(x_plan_mutable_target "$file" "plan decision set")
  [[ $id =~ ^OD-[0-9]{3}$ ]] || x_die "plan decision set: invalid --id"
  [[ " ${X_PLAN_FACETS[*]} " == *" $facet "* ]] || x_die "plan decision set: invalid --facet"
  if x_plan_is_placeholder "$question" || x_plan_is_placeholder "$decision" ||
     [[ $question == *$'\n'* || $decision == *$'\n'* || $question == *$'\t'* || $decision == *$'\t'* ||
        $question == *"|"* || $decision == *"|"* ]]; then
    x_die "plan decision set: question and decision must be substantive single-cell text"
  fi
  x_require_value --state "$state"

  local scope lock
  scope=$(x_plan_scope_for "$file")
  lock="$scope/.xdh-plan.lock"
  x_lock "$lock"
  if ! x_plan_decision_set_locked "$file" "$id" "$facet" "$question" "$decision" "$state"; then
    x_unlock
    return 1
  fi
  x_unlock
  x_emit X_PLAN_DECISION_SET "$id"
}

x_plan_decision_set_locked() {
  local file=$1 id=$2 facet=$3 question=$4 decision=$5 state=$6 fp fingerprint row
  fp=$(x_plan_compute_fingerprint "$file") || return 1
  case $state in
    pending) fingerprint=— ;;
    "accepted@$fp") fingerprint=$fp ;;
    accepted@*) x_plan_blocker "decision=$id state=stale expected=accepted@$fp actual=$state"; return 1 ;;
    *) x_plan_blocker "decision=$id state=invalid"; return 1 ;;
  esac
  row="| $id | $facet | $question | $decision | $state | $fingerprint |"

  local tag eid efacet equestion edecision estate efingerprint matches=0 mode=insert
  while IFS=$'\t' read -r tag eid efacet equestion edecision estate efingerprint; do
    if [[ $tag != valid ]]; then
      x_plan_blocker "decision=${eid:-unknown} status=invalid-schema"
      return 1
    fi
    [[ $tag == valid && $eid == "$id" ]] || continue
    matches=$(( matches + 1 ))
    if [[ $efacet == "$facet" && $equestion == "$question" && $edecision == "$decision" &&
          $estate == "$state" && $efingerprint == "$fingerprint" ]]; then
      mode=noop
    elif [[ $estate == pending && $state == "accepted@$fp" &&
            $efacet == "$facet" && $equestion == "$question" ]]; then
      mode=replace
    else
      x_plan_blocker "decision=$id status=id-collision"
      return 1
    fi
  done < <(x_plan_owner_decisions "$file")
  (( matches <= 1 )) || { x_plan_blocker "decision=$id status=id-collision"; return 1; }
  if (( matches == 0 )) && [[ $state != pending ]]; then
    x_plan_blocker "decision=$id status=invalid-transition expected=pending"
    return 1
  fi
  [[ $mode == noop ]] || x_plan_decision_write "$file" "$id" "$row" "$mode"
  x_emit X_PLAN_DECISION_REUSED "$([[ $mode == noop ]] && printf yes || printf no)"
  x_emit X_PLAN_FINGERPRINT "$fp"
}

x_plan_decision_write() {
  local file=$1 id=$2 row=$3 mode=$4 tmp
  tmp=$(mktemp "$(dirname -- "$file")/.xdh-field.XXXXXX")
  awk -F'|' -v id="$id" -v row="$row" -v mode="$mode" '
    { clean=$0; sub(/\r$/, "", clean); eol=($0 ~ /\r$/ ? "\r" : "") }
    clean ~ /^## / { in_decisions=(clean == "## Owner Decisions") }
    in_decisions && mode == "replace" && clean ~ /^\|/ {
      cell=$2; gsub(/^[ \t]+|[ \t]+$/, "", cell)
      if (cell == id) { print row eol; done=1; next }
    }
    { print }
    in_decisions && mode == "insert" && clean ~ /^\|[-: |]+\|/ && !done {
      print row eol
      done=1
    }
    END { if (!done) exit 9 }
  ' "$file" > "$tmp" || { rm -f "$tmp"; x_plan_blocker "decision=$id status=table-write-failed"; return 1; }
  x_atomic_write "$file" < "$tmp"
  rm -f "$tmp"
}

# Writing wrapper: validate, then atomically refresh the advisory fingerprint and
# Planning Complete. Never changes Status.
x_plan_check() {
  local file=$1
  [[ -n $file && -f $file ]] || x_die "plan check: missing item file"
  file=$(x_plan_mutable_target "$file" "plan check")

  local scope lock
  scope=$(x_plan_scope_for "$file")
  lock="$scope/.xdh-plan.lock"
  x_lock "$lock"

  if ! x_plan_validate "$file"; then
    x_unlock
    return 1
  fi
  local fp
  fp=$(x_plan_compute_fingerprint "$file") || { x_unlock; return 1; }

  x_fields_set "$file" "Planning input fingerprint" "$fp" "Planning Complete" "completed@$fp"
  x_unlock

  x_emit X_PLAN_CHECK PASS
  x_emit X_PLAN_FINGERPRINT "$fp"
}

# Single non-reentrant lock: validate, recheck Owner/WG/branch/worktree
# consistency, revalidate the raw item, then set Execution Ready + Status in one
# atomic replacement.
x_plan_ready() {
  local file=$1
  [[ -n $file && -f $file ]] || x_die "plan ready: missing item file"
  file=$(x_plan_mutable_target "$file" "plan ready")
  local id fp
  id=$(x_plan_item_id "$file")

  local scope lock
  scope=$(x_plan_scope_for "$file")
  lock="$scope/.xdh-plan.lock"
  x_lock "$lock"

  # Byte-exact snapshot taken before validation: any concurrent edit to the
  # item must abort readiness before it can be stamped ready. A SHA-256 over the
  # file bytes (not a command substitution of `cat`, which strips trailing
  # newlines) means even a trailing-LF-only edit is detected.
  local raw_before
  raw_before=$(x_plan_file_sha256 "$file") || { x_unlock; return 1; }

  if ! x_plan_validate "$file"; then
    x_unlock
    return 1
  fi
  [[ $(x_plan_file_sha256 "$file") == "$raw_before" ]] || { x_plan_blocker "item=changed-during-validation"; x_unlock; return 1; }

  fp=$(x_plan_compute_fingerprint "$file") || { x_unlock; return 1; }
  [[ $(x_field_get "$file" "Planning Complete") == "completed@$fp" ]] || { x_plan_blocker "planning-complete=missing expected=completed@$fp"; x_unlock; return 1; }

  local owner wgid
  owner=$(x_field_get "$file" Owner)
  wgid=$(x_field_get "$file" WG)
  [[ -n $owner && $owner != — && $owner != - ]] || { x_plan_blocker "owner=missing"; x_unlock; return 1; }

  # Resolve the owning Work Group (exactly one).
  local wgfile=""
  if [[ -z $wgid ]]; then
    wgfile=$(x_plan_unique_containing_wg "$scope" "$id")
  elif [[ $wgid == — || $wgid == - ]]; then
    x_plan_blocker "wg=missing id=$wgid"; x_unlock; return 1
  else
    wgfile=$(x_plan_find_wg "$scope" "$wgid")
  fi
  [[ -n $wgfile ]] || { x_plan_blocker "wg=missing id=${wgid:-fallback}"; x_unlock; return 1; }

  # WG consistency.
  local wg_owner wg_items wg_branch wg_worktree
  wg_owner=$(x_field_get "$wgfile" Owner)
  wg_items=$(x_field_get "$wgfile" "Work items")
  wg_branch=$(x_field_get "$wgfile" Branch | tr -d '`')
  wg_worktree=$(x_field_get "$wgfile" Worktree | tr -d '`')

  [[ $wg_owner == "$owner" ]] || { x_plan_blocker "wg=$wgid status=owner-mismatch expected=$owner actual=$wg_owner"; x_unlock; return 1; }
  local item_count
  item_count=$(printf '%s' "$wg_items" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -cFx "$id" || true)
  [[ $item_count -eq 1 ]] || { x_plan_blocker "wg=$wgid status=item-count item=$id count=${item_count:-0}"; x_unlock; return 1; }
  [[ -n $wg_branch && $wg_branch != — && $wg_branch != - ]] || { x_plan_blocker "wg=$wgid status=branch-missing"; x_unlock; return 1; }
  [[ -n $wg_worktree && $wg_worktree != — && $wg_worktree != - ]] || { x_plan_blocker "wg=$wgid status=worktree-missing"; x_unlock; return 1; }

  x_resolve_paths
  if ! git -C "$X_MAIN_ROOT" worktree list --porcelain | grep -Fxq "worktree $wg_worktree"; then
    x_plan_blocker "wg=$wgid status=worktree-unregistered path=$wg_worktree"; x_unlock; return 1
  fi
  [[ -e "$wg_worktree/.git" ]] || { x_plan_blocker "wg=$wgid status=worktree-stale path=$wg_worktree"; x_unlock; return 1; }
  local actual_branch
  actual_branch=$(git -C "$wg_worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
  [[ $actual_branch == "$wg_branch" ]] || { x_plan_blocker "wg=$wgid status=branch-mismatch expected=$wg_branch actual=${actual_branch:-unknown}"; x_unlock; return 1; }

  # The raw item must still match the pre-validation snapshot before the one
  # atomic ready write.
  [[ $(x_plan_file_sha256 "$file") == "$raw_before" ]] || { x_plan_blocker "item=changed-during-ready"; x_unlock; return 1; }

  x_fields_set "$file" "Execution Ready" "completed@$fp" "Status" "ready"
  x_unlock

  x_emit X_PLAN_READY "$id"
}

# Find the WG document for an ID within a scope; empty when zero or multiple
# match.
x_plan_find_wg() {
  local scope=$1 wgid=$2 file found="" n=0
  local search_dirs=("$scope/work-groups" "$scope")
  local d
  for d in "${search_dirs[@]}"; do
    [[ -d $d ]] || continue
    for file in "$d"/"${wgid}-"*.md; do
      [[ -f $file ]] || continue
      found=$file
      n=$(( n + 1 ))
    done
  done
  if (( n == 1 )); then printf '%s' "$found"; fi
}

# Unique same-scope WG whose exact-token Work items contain the item ID; empty
# when zero or multiple match.
x_plan_unique_containing_wg() {
  local scope=$1 id=$2 file found="" n=0
  local search_dirs=("$scope/work-groups" "$scope")
  local d
  for d in "${search_dirs[@]}"; do
    [[ -d $d ]] || continue
    for file in "$d"/WG-*.md; do
      [[ -f $file ]] || continue
      if [[ " $(x_field_get "$file" "Work items" | tr ',' ' ') " == *" $id "* ]]; then
        found=$file
        n=$(( n + 1 ))
      fi
    done
  done
  if (( n == 1 )); then printf '%s' "$found"; fi
}

# Design artifact scaffold: deterministic project-local directory, reused for the
# same slug+fingerprint, replaced rollback-safely for a changed fingerprint.
x_design_prepare() {
  local slug="" fingerprint="" cycle="" dir="" image_generate="" image_display="" image_compare=""
  while (( $# )); do
    case $1 in
      --slug) slug=$2; shift 2 ;;
      --fingerprint) fingerprint=$2; shift 2 ;;
      --for) fingerprint=$2; shift 2 ;;
      --cycle) cycle=$2; shift 2 ;;
      --dir) dir=$2; shift 2 ;;
      --image-generate) image_generate=$2; shift 2 ;;
      --image-display) image_display=$2; shift 2 ;;
      --image-compare) image_compare=$2; shift 2 ;;
      *) x_die "design prepare: unknown option $1" ;;
    esac
  done
  x_require_value --slug "$slug"
  x_require_value --fingerprint "$fingerprint"
  x_require_value --image-generate "$image_generate"
  x_require_value --image-display "$image_display"
  x_require_value --image-compare "$image_compare"
  local capability
  for capability in "$image_generate" "$image_display" "$image_compare"; do
    [[ $capability == available || $capability == unavailable ]] ||
      x_die "design prepare: capability values must be available or unavailable"
  done
  slug=$(x_slugify "$slug")
  [[ -n $slug ]] || x_die "design prepare: --slug must contain an alphanumeric character"

  local scope root target scope_real
  if [[ -n $dir ]]; then
    scope=$dir
  else
    scope=$(x_scope_dir_for "$cycle" "")
  fi
  x_resolve_paths
  scope_real=$(x_plan_realpath "$scope") || x_die "design prepare: invalid scope"
  [[ -d $scope_real && $scope_real == "$X_DEV_HUB"/* ]] || x_die "design prepare: scope outside .dev-hub"
  [[ ! -L "$scope_real/artifacts" && ! -L "$scope_real/artifacts/design" ]] || x_die "design prepare: symlinked design root"
  root="$scope_real/artifacts/design"
  mkdir -p "$root"
  [[ ! -L "$root/$slug" ]] || x_die "design prepare: symlinked design target"
  target="$root/$slug"

  if [[ -f "$target/manifest.md" ]] && LC_ALL=C grep -Fxq "Fingerprint: $fingerprint" "$target/manifest.md"; then
    x_emit X_DESIGN_DIR "$target"
    x_emit X_DESIGN_REUSED yes
    return 0
  fi

  # Stage the replacement scaffold, then swap rollback-safely: the old scaffold
  # is preserved until the new one is in place, and never accumulates versions.
  local tmp
  tmp=$(mktemp -d "$root/.design.XXXXXX")
  {
    printf 'Fingerprint: %s\n' "$fingerprint"
    printf 'Image Generate: %s\n' "$image_generate"
    printf 'Image Display: %s\n' "$image_display"
    printf 'Image Compare: %s\n' "$image_compare"
  } > "$tmp/manifest.md"
  printf '# %s\n\n' "$slug" > "$tmp/brief.md"
  printf '# Variant 01 (text summary)\n\n' > "$tmp/variant-01.md"
  printf '# Selection\n\n' > "$tmp/selection.md"

  if [[ -e $target ]]; then
    local backup
    backup=$(mktemp -d "$root/.design-old.XXXXXX")
    mv "$target" "$backup/prev"
    if mv "$tmp" "$target"; then
      rm -rf "$backup"
    else
      mv "$backup/prev" "$target" 2>/dev/null || true
      rm -rf "$backup" "$tmp"
      x_die "design prepare: cannot replace $target"
    fi
  else
    mv "$tmp" "$target" || { rm -rf "$tmp"; x_die "design prepare: cannot create $target"; }
  fi

  x_emit X_DESIGN_DIR "$target"
  x_emit X_DESIGN_REUSED no
}
