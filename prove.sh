#!/bin/sh
# Prove every verification condition of json2dir.mlw. Each goal (after split_vc) is sent to
# Z3, CVC4 and Alt-Ergo; it counts as proved when at least one of them answers Valid.
# Exits non-zero, listing the goals, if any goal stays unproved.
# usage: prove.sh <why3 wrapper> [time limit in seconds]
why3=$1
limit=${2:-10}
cd "$(dirname "$0")" || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
for p in z3 cvc4 alt-ergo; do
  "$why3" prove -a split_vc -P "$p" -t "$limit" json2dir.mlw > "$tmp/$p.out" 2>&1 &
done
wait
for p in z3 cvc4 alt-ergo; do
  # one line per goal: "<goal description><TAB><result>"
  awk '/^File |^Goal /{g=$0; next} /^Sub-goal /{g=g" "$0; next}
       /^Prover result is: /{sub(/^Prover result is: /,""); print g "	" $0}' "$tmp/$p.out" > "$tmp/$p.res"
done
total=$(wc -l < "$tmp/z3.res")
if [ "$total" -eq 0 ]; then cat "$tmp/z3.out"; echo "prove.sh: no goals found" >&2; exit 1; fi
for p in cvc4 alt-ergo; do
  if [ "$(wc -l < "$tmp/$p.res")" -ne "$total" ]; then cat "$tmp/$p.out"; echo "prove.sh: $p saw a different goal list" >&2; exit 1; fi
done
paste "$tmp/z3.res" "$tmp/cvc4.res" "$tmp/alt-ergo.res" | awk -F '\t' -v total="$total" '
  { by = ""
    if ($2 ~ /^Valid/) by = by " z3"
    if ($4 ~ /^Valid/) by = by " cvc4"
    if ($6 ~ /^Valid/) by = by " alt-ergo"
    if (by == "") { bad++; print "UNPROVED: " $1 } else { ok++; for (i = 1; i <= 3; i++) if (index(by, " " (i==1?"z3":i==2?"cvc4":"alt-ergo"))) n[i]++ }
  }
  END { printf "why3 prove: %d/%d goals proved (z3 %d, cvc4 %d, alt-ergo %d)\n", ok, total, n[1], n[2], n[3]
        exit bad > 0 }'
