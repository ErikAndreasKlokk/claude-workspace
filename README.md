# claude-workspace

Config + tooling to run **Claude Code from my phone**, as a container in the
Talos/K8s homelab, reached over Tailscale via [code-server](https://github.com/coder/code-server).

This repo is the **workspace root**: on pod boot it's cloned into
`/home/coder/workspace`, and `bootstrap.sh` clones the six project repos in as
subdirectories, reconstructing the `E:\Koder` layout. The GitHub repos are the
source of truth; uncommitted work lives on the pod's PVC (persists across
restarts, but push early).

## What's here

| Path | Purpose |
| --- | --- |
| `CLAUDE.md` | Linux-ported workspace guidance (paths, bash, in-cluster kubectl) |
| `.claude/skills/` | `git-operations`, `new-homelab-project` (ported to bash), `new-web-project` |
| `bootstrap.sh` | Clones/updates the six project repos into the workspace |
| `Dockerfile` | code-server + Node 20 + Claude Code + kubectl + kubeseal |
| `.github/workflows/docker-publish.yml` | Builds/pushes `ghcr.io/erikandreasklokk/claude-workspace:main` |

The Kubernetes manifests live in the **homelab** repo, not here:
- `homelab/applications/claude-code/` — the app (Deployment, PVC, RBAC, Service, Tailscale Ingress)
- `homelab/setup-homelab/tailscale/` — the Tailscale operator (install once)

## First-time setup

1. **Push this repo** to `github.com/ErikAndreasKlokk/claude-workspace` (triggers the image build).
2. **Install the Tailscale operator** (one-time):
   - Create an OAuth client in the Tailscale admin console (Devices:core + Auth Keys, write).
   - Seal it into `homelab/setup-homelab/tailscale/operator-oauth-sealed-secret.yaml` (instructions in that file).
   - Apply: `kubectl kustomize --enable-helm setup-homelab/tailscale/ | kubectl apply -f -`
3. **Seal the code-server password** into
   `homelab/applications/claude-code/code-server-sealed-secret.yaml` (instructions in that file).
4. **Commit + push homelab** — ArgoCD auto-syncs `applications/claude-code/`.
5. **One-time Claude login:** `kubectl exec -it -n claude-code deploy/claude-code -- claude`
   and complete the browser login. The credential persists on the PVC, so this
   is only needed again if the token is revoked/expires.
6. From the phone (Tailscale on): open `https://claude-code.<your-tailnet>.ts.net`,
   enter the code-server password, open a terminal, run `claude`.

## Auth renewal

Access tokens refresh automatically. A full re-login is rare; when needed, do it
from the phone via code-server (browser + integrated terminal in one app), or
re-run the `kubectl exec … claude` step from a desktop.
