#!/usr/bin/env bash
#
# loc.sh — tech-debt radar: largest Elixir source files, biggest first.
#
# Usage:
#   scripts/loc.sh                 # lib/ files >= 400 lines
#   scripts/loc.sh 300             # lib/ files >= 300 lines
#   scripts/loc.sh 300 test        # test/ files >= 300 lines
#   scripts/loc.sh 0 lib | head    # everything, largest first
#
# Prints a LINES/FILE table sorted descending, a count of offenders,
# and the total lines across them. Keep the top of this list short.
set -euo pipefail

min="${1:-400}"
root="${2:-lib}"

rows="$(
  find "$root" -type f -name '*.ex' -print0 \
    | xargs -0 wc -l \
    | awk -v m="$min" '$2 != "total" && $1 >= m { printf "%6d\t%s\n", $1, $2 }' \
    | sort -rn
)"

printf '%6s  %s\n' "LINES" "FILE"
if [ -n "$rows" ]; then
  printf '%s\n' "$rows" | awk -F'\t' '{ printf "%6d  %s\n", $1, $2 }'
  n="$(printf '%s\n' "$rows" | wc -l | tr -d ' ')"
  sum="$(printf '%s\n' "$rows" | awk -F'\t' '{ s += $1 } END { print s }')"
  printf -- '----\n%d file(s) >= %s lines, %d lines total\n' "$n" "$min" "$sum"
else
  printf -- '(none >= %s lines under %s/)\n' "$min" "$root"
fi
