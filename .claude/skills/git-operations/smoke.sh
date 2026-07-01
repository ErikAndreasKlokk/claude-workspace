#!/usr/bin/env bash
# smoke.sh — one status line per repo in the workspace.
# Prints: name, [branch], ahead/behind/uncommitted summary, last commit.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

for dir in "$ROOT"/*/; do
  git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null || continue
  name="$(basename "$dir")"
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"

  # ahead/behind vs upstream (if one is configured)
  ab=""
  if git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' &>/dev/null; then
    read -r behind ahead < <(git -C "$dir" rev-list --left-right --count '@{u}...HEAD')
    [ "$ahead"  -gt 0 ] && ab+="↑$ahead "
    [ "$behind" -gt 0 ] && ab+="↓$behind "
  fi

  dirty="$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')"
  if [ "$dirty" -gt 0 ]; then state="${ab}${dirty} uncommitted"; else state="${ab}clean"; fi

  last="$(git -C "$dir" log -1 --format='%h %s' 2>/dev/null | cut -c1-50)"
  printf '%-16s [%s]  %-18s %s\n' "$name" "$branch" "$state" "$last"
done
