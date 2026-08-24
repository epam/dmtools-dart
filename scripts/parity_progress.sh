#!/usr/bin/env bash
# Phase 6 parity tracker: counts closed vs open P6-* items across the
# wave files in phases/ (the global GOAL.md keeps only the master table).
# Prints {"score": N, "max": M, "open": M-N, "waves": {...}}; exit 0 always.
set -u
cd "$(dirname "$0")/.." || exit 1

total_done=0
total_open=0
total_prog=0
wave_json=''

for f in phases/phase6-*.md; do
  [ -e "$f" ] || continue
  wave=$(basename "$f" | sed -E 's/phase6-(w[0-9]+)-.*/\1/' | tr 'a-z' 'A-Z')
  d=$(grep -cE '^- \[x\] \*\*P6-' "$f" || true)
  o=$(grep -cE '^- \[ \] \*\*P6-' "$f" || true)
  p=$(grep -cE '^- \[~\] \*\*P6-' "$f" || true)
  total_done=$((total_done + d))
  total_open=$((total_open + o))
  total_prog=$((total_prog + p))
  status=$(sed -n 's/^status: *\([a-z-]*\).*/\1/p' "$f" | head -1)
  wave_json="${wave_json}\"${wave}\":{\"done\":${d},\"open\":${o},\"in_progress\":${p},\"status\":\"${status}\"},"
done
wave_json=${wave_json%,}
total=$((total_done + total_open + total_prog))
printf '{"score": %d, "max": %d, "open": %d, "in_progress": %d, "waves": {%s}}\n' \
  "$total_done" "$total" "$total_open" "$total_prog" "$wave_json"
exit 0
