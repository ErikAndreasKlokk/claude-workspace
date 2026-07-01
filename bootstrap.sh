#!/usr/bin/env bash
# bootstrap.sh — reconstruct the E:\Koder workspace inside the pod.
#
# Best-effort: a single repo failing (e.g. a private repo with no token) is
# logged and skipped, never aborts. Always exits 0 so the pod comes up.
#
# If GITHUB_TOKEN is set, git is configured to use it for github.com — this
# enables cloning private repos AND pushing (public repos clone anonymously
# but still need auth to push).
#
#   ./bootstrap.sh
#
set -uo pipefail
export GIT_TERMINAL_PROMPT=0   # fail fast instead of hanging on an auth prompt

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global \
    url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf \
    "https://github.com/"
  echo ">> GitHub token configured for github.com (clone + push enabled)"
else
  echo ">> no GITHUB_TOKEN — public repos only, pushing will fail"
fi

# folder|clone-url  (PortfolioV2 folder tracks the renamed "Portfolio" repo)
REPOS=(
  "bolig|https://github.com/ErikAndreasKlokk/Bolig.git"
  "Budgeting|https://github.com/ErikAndreasKlokk/Budgeting.git"
  "KlokkProjects|https://github.com/ErikAndreasKlokk/KlokkProjects.git"
  "homelab|https://github.com/ErikAndreasKlokk/homelab.git"
  "PortfolioV2|https://github.com/ErikAndreasKlokk/Portfolio.git"
)

skipped=""
for entry in "${REPOS[@]}"; do
  dir="${entry%%|*}"
  url="${entry##*|}"
  if [ -d "$dir/.git" ]; then
    echo ">> $dir exists — fetching + fast-forward"
    git -C "$dir" fetch --quiet origin && git -C "$dir" pull --ff-only \
      || echo "   ($dir: pull skipped — local work or offline)"
  else
    echo ">> cloning $dir"
    if ! git clone --quiet "$url" "$dir"; then
      echo "   !! could not clone $dir (private without token, or offline) — skipping"
      skipped+=" $dir"
    fi
  fi
done

if [ -n "$skipped" ]; then
  echo "Workspace ready at $ROOT (skipped:$skipped)"
else
  echo "Workspace ready at $ROOT"
fi
exit 0
