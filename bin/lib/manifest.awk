# Reader for the installation manifest written by bin/lib/common.sh.
#
# The manifest is JSON so it stays inspectable by humans and by jq, but this
# repository must stay dependency-free, so the writer keeps a deliberately
# regular shape: top-level scalars are indented two spaces, arrays and maps are
# emitted on one line, and every entry object is one line. That is enough for a
# scanner that only has to understand quoted strings.
#
# Usage: awk -f manifest.awk -v mode=scalar -v key=commit install.json
#   mode=scalar   print the value of a top-level string/number key
#   mode=array    print each element of a top-level string array, one per line
#   mode=map      print "name<TAB>value" for each pair of a top-level object
#   mode=entries  print "agent<TAB>kind<TAB>path<TAB>target" per managed entry

# Collect every JSON string in s into arr[1..n]; returns n.
function collect(s, arr,    i, n, c, esc, instr, cur, count) {
  count = 0; instr = 0; esc = 0; cur = ""
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (instr) {
      if (esc) {
        if (c == "n") c = "\n"
        else if (c == "t") c = "\t"
        cur = cur c
        esc = 0
      } else if (c == "\\") {
        esc = 1
      } else if (c == "\"") {
        arr[++count] = cur
        cur = ""
        instr = 0
      } else {
        cur = cur c
      }
    } else if (c == "\"") {
      instr = 1
    }
  }
  return count
}

# The remainder of a top-level "key": ... line, or "" when the line is not it.
function tail(line, wanted,    prefix) {
  prefix = "  \"" wanted "\": "
  if (substr(line, 1, length(prefix)) != prefix) return ""
  return substr(line, length(prefix) + 1)
}

mode == "scalar" && !found {
  rest = tail($0, key)
  if (rest != "") {
    sub(/,$/, "", rest)
    if (substr(rest, 1, 1) == "\"") {
      n = collect(rest, parts)
      if (n >= 1) print parts[1]
    } else {
      print rest
    }
    found = 1
  }
  next
}

mode == "array" && !found {
  rest = tail($0, key)
  if (rest != "") {
    n = collect(rest, parts)
    for (i = 1; i <= n; i++) print parts[i]
    found = 1
  }
  next
}

mode == "map" && !found {
  rest = tail($0, key)
  if (rest != "") {
    n = collect(rest, parts)
    for (i = 1; i + 1 <= n; i += 2) print parts[i] "\t" parts[i + 1]
    found = 1
  }
  next
}

mode == "entries" && /^    \{"agent":/ {
  n = collect($0, parts)
  delete entry
  for (i = 1; i + 1 <= n; i += 2) entry[parts[i]] = parts[i + 1]
  print entry["agent"] "\t" entry["kind"] "\t" entry["path"] "\t" entry["target"]
}
