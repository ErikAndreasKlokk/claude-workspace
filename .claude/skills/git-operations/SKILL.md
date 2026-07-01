---
name: git-operations
description: Git operations across the workspace. Use when pulling latest changes, committing, pushing, checking status across all repos, or doing any git workflow on bolig, Budgeting, homelab, KlokkProjects, moviejus, or PortfolioV2.
---

## Overview

Six independent git repos live under `/home/coder/workspace` (cloned by `bootstrap.sh`). All are on `main`, all push to `github.com/ErikAndreasKlokk/*` except `moviejus` (→ `Herjuus/moviejus`). The `PortfolioV2/` folder tracks the repo GitHub renamed `PortfolioV2` → `Portfolio`. Shell is **bash** on Linux.

---

## Workspace status (run this first)

```bash
bash /home/coder/workspace/.claude/skills/git-operations/smoke.sh
```

Output: one line per repo — branch, ahead/behind/uncommitted count, last commit.

---

## Pull latest for one project

```bash
git -C /home/coder/workspace/PortfolioV2 pull --ff-only
```

Use `--ff-only` — it fails loudly if there are local commits that would require a merge, instead of silently creating a merge commit.

To pull all clean repos at once:

```bash
for p in /home/coder/workspace/*/; do
  git -C "$p" rev-parse --is-inside-work-tree &>/dev/null || continue
  if [ -z "$(git -C "$p" status --porcelain)" ]; then
    echo "Pulling $(basename "$p")..."
    git -C "$p" pull --ff-only
  else
    echo "Skipping $(basename "$p") — has uncommitted changes"
  fi
done
```

---

## Commit and push

```bash
# Stage specific files
git -C /home/coder/workspace/PortfolioV2 add src/routes/homeoffice/+page.svelte

# Stage everything (check status first)
git -C /home/coder/workspace/PortfolioV2 add -A

# Commit
git -C /home/coder/workspace/PortfolioV2 commit -m "short description of change"

# Push
git -C /home/coder/workspace/PortfolioV2 push
```

---

## Check what's uncommitted

```bash
git -C /home/coder/workspace/Budgeting status --short
```

Untracked files show as `??`. Modified files show as ` M` (working tree) or `M ` (staged).

---

## Commit message format

```
type(scope): description
```

Common types:

| Type | When to use |
|---|---|
| `feat` | new feature or visible behaviour change |
| `fix` | bug fix |
| `refactor` | code change that isn't a feature or fix |
| `chore` | build, deps, config, tooling — nothing that ships |
| `style` | formatting, whitespace, no logic change |
| `docs` | documentation only |

`scope` is the affected area — component name, route, feature, or module (e.g. `dashboard`, `auth`, `homeoffice`, `db`). Keep it short. Omit if the change is truly cross-cutting.

`description` is lowercase, no trailing period, present tense ("add" not "added").

Examples:
```
feat(investments): add year-over-year comparison chart
fix(auth): redirect to /auth on expired session
refactor(db): extract query helpers into separate module
chore(deps): bump sveltekit to 2.21.0
style(sidebar): fix inconsistent icon spacing
```

---

## Gotchas

- **PortfolioV2 remote moved** — GitHub renamed the repo from `PortfolioV2` to `Portfolio`. The local folder is still `PortfolioV2/` and `bootstrap.sh` clones the `Portfolio.git` URL into it. Push still works via redirect (GitHub preserves the old URL); the `"This repository moved…"` warning is expected and harmless.
- **No root-level git repo** — `/home/coder/workspace` itself is a checkout of `claude-workspace`, whose `.gitignore` excludes the six project dirs. Git commands for a project need `-C <project-path>`.
- **Budgeting / KlokkProjects have many uncommitted files** — this is expected in-progress work, not an error. Don't commit those unless explicitly asked.
- **This is a Linux/bash environment** — `&&` chaining works; there is no PowerShell/WSL layer.
