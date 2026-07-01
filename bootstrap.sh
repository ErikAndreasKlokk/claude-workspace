#!/usr/bin/env bash
# bootstrap.sh — reconstruct the E:\Koder workspace inside the pod.
#
# Run from the workspace root (the checkout of claude-workspace). Clones each
# project repo as a subdirectory, or fast-forwards it if already present. All
# repos are public, so no credentials are needed to clone.
#
#   ./bootstrap.sh
#
set -euo pipefail

# Directory this script lives in == workspace root.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# folder<TAB>clone-url  (PortfolioV2 folder tracks the renamed "Portfolio" repo)
REPOS=(
  "bolig|https://github.com/ErikAndreasKlokk/Bolig.git"
  "Budgeting|https://github.com/ErikAndreasKlokk/Budgeting.git"
  "KlokkProjects|https://github.com/ErikAndreasKlokk/KlokkProjects.git"
  "homelab|https://github.com/ErikAndreasKlokk/homelab.git"
  "moviejus|https://github.com/Herjuus/moviejus.git"
  "PortfolioV2|https://github.com/ErikAndreasKlokk/Portfolio.git"
)

for entry in "${REPOS[@]}"; do
  dir="${entry%%|*}"
  url="${entry##*|}"
  if [ -d "$dir/.git" ]; then
    echo ">> $dir exists — fetching + fast-forward"
    git -C "$dir" fetch --quiet origin
    git -C "$dir" pull --ff-only || echo "   ($dir has local work; skipped ff)"
  else
    echo ">> cloning $dir"
    git clone --quiet "$url" "$dir"
  fi
done

echo "Done. Workspace ready at $ROOT"
