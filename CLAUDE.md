# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Where this is running

This is the **mobile / homelab** copy of the `E:\Koder` workspace, running as Claude Code inside a container **in the Talos/K8s cluster** (reached from a phone over Tailscale, via code-server). Consequences that differ from the Windows workstation:

- The workspace root is `/home/coder/workspace` (a checkout of the `claude-workspace` repo); the project repos are cloned in as subdirectories by `bootstrap.sh`.
- The shell is **bash**, not PowerShell. Commands written for PowerShell in per-project docs need bash equivalents.
- `kubectl` / `kubeseal` are **native** here and authenticate via the pod's in-cluster ServiceAccount — there is **no** `wsl -- bash -lc "…"` wrapper (that was a Windows-only detail) and no external kubeconfig.
- The canonical source of truth is always the GitHub repos. Uncommitted work lives on the pod's PVC and survives restarts, but push early — a lost PVC loses anything unpushed.

## What this directory is

This workspace is **not a single repo** — it is a workspace containing six independent projects, each with its own git history, dependencies, and toolchain. There is no root-level package, build, or shared config. Always operate inside a specific project subdirectory.

## Projects

| Folder | Stack | Has own CLAUDE.md |
| --- | --- | --- |
| [bolig](bolig/) | SvelteKit 5 + Drizzle + Postgres + Tailwind v4, adapter-node (Finn.no boligjakt-skraper, Discord-varsler) | no — see below |
| [Budgeting](Budgeting/) | SvelteKit 5 + Drizzle + Postgres, session-cookie auth, Argon2 | yes — read it before editing |
| [KlokkProjects](KlokkProjects/) | SvelteKit 5 + Sanity + Algolia (Drive Electric docs site) | yes — read it before editing |
| [homelab](homelab/) | Proxmox + Talos + Kubernetes + ArgoCD (GitOps), Cilium, cert-manager, sealed-secrets | yes — read it before editing |
| [moviejus](moviejus/) | Qwik + Qwik City + Fastify adapter + Tailwind v4 + daisyUI, TMDB API client | no — see below |
| [PortfolioV2](PortfolioV2/) | SvelteKit 5 + adapter-node + Tailwind v3 + Shiki (code blocks) | no — see below |

> `PortfolioV2/` tracks the GitHub repo that was renamed `PortfolioV2` → `Portfolio`; the folder name is kept for continuity.

**Workflow rule:** before doing work in a project that has its own CLAUDE.md, read that file first — it overrides anything generic here.

## bolig — quick reference

A "boligjakt" tool: scrapes Finn.no real-estate listings (3–5 mill. kr, Oslo + Bærum) into Postgres, sorts by transit time to work (Entur), computes affordability, and posts Discord webhooks for new listings and price drops. Deployed to the homelab (`homelab/applications/bolig/`, GitHub repo `ErikAndreasKlokk/Bolig`, images `ghcr.io/erikandreasklokk/bolig` + `…/bolig-migrate`). The scraper runs every ~30 min.

- `npm run dev` / `npm run build` / `npm run preview` — standard SvelteKit (adapter-node, `node build`)
- `npm run check` — `svelte-kit sync` + `svelte-check` (only correctness gate; no test runner)
- `npm run lint` / `npm run format` — Prettier + ESLint
- `npm run db:push` — `drizzle-kit push` to sync `schema.ts` to the DB (no SQL migration files; the `bolig-migrate` image runs `drizzle-kit push --force`, see `Dockerfile.migrate`)
- Required env: `DATABASE_URL`, `DISCORD_WEBHOOK_URL`
- Key server modules under `src/lib/server/`: `finn.ts` (HTML scraping — Finn has no public JSON API), `entur.ts` (geocode + transit time), `scraper.ts` (orchestration + upsert + price-history + notifications), `discord.ts` (webhooks). Data model in `db/schema.ts`: `listings`, `price_history`, `user_settings`.
- Two Dockerfiles: `Dockerfile` (app) and `Dockerfile.migrate` (one-shot DB sync job).
- **Deploying / verifying a deploy:** push to `main` (triggers the `docker-publish.yml` CI build of the `:main` images), then use the **`new-homelab-project`** skill for all cluster work — confirming the CI run, restarting the deployment to pull the reused `:main` tag, and checking rollout/pod status. See `homelab/CLAUDE.md` for details.

## moviejus — quick reference

Qwik City SSR app for browsing movies/series via TMDB. Multiple server adapters live under `adapters/` (`express`, `fastify`, `node-server`); the default `npm run build` targets Fastify (`adapters/fastify/vite.config.ts`) and `npm run serve` runs `server/entry.fastify`.

- `npm run dev` — Vite SSR dev server
- `npm run build` — full Qwik build (client + server via Fastify adapter)
- `npm run build.types` — `tsc --noEmit` type check
- `npm run lint` / `npm run fmt` / `npm run fmt.check` — ESLint and Prettier (no test runner configured)
- `npm run preview` — local production preview
- Required env: `TMDB_ACCESS_TOKEN`
- Node engine: `^18.17.0 || ^20.3.0 || >=21.0.0` (sharp needs Node-API v9)
- Dockerfile present; the image runs the Fastify entry.

Entry files for each adapter (`src/entry.express.tsx`, `src/entry.fastify.tsx`, `src/entry.node-server.tsx`) are paired with the matching `adapters/<name>/vite.config.ts` — if you change deployment target, change both.

## PortfolioV2 — quick reference

Personal portfolio site, SvelteKit 5 + `@sveltejs/adapter-node`. Uses `@sveltejs/enhanced-img` for image processing, Shiki + `shiki-transformer-copy-button` for syntax-highlighted code blocks, `@formkit/auto-animate` for animations, and Tailwind v3 (note: older than the v4 used in `Budgeting` and `KlokkProjects`).

- `npm run dev` / `npm run build` / `npm run preview` — standard SvelteKit
- `npm run check` — `svelte-kit sync` + `svelte-check` (only correctness gate; no lint or test scripts configured)
- No `.env.example` checked in; runtime config (if any) lives in route loaders.

## Shell note

This instance runs on **Linux with bash**. Any commands shown in per-project CLAUDE.md files written for PowerShell (`wsl -- bash -lc "…"`, `Get-ChildItem`, `$env:VAR=…`, `Copy-Item \\wsl$\…`) need their bash equivalents here — most importantly, run `kubectl`/`kubeseal` directly (no `wsl --` prefix).
