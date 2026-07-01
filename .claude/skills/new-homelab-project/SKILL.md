---
name: new-homelab-project
description: Scaffold a new project for the homelab. Creates Dockerfile, GitHub Actions CI workflow, and Kubernetes/ArgoCD manifests in homelab/applications/. Also use for cluster operations — checking deployment status, viewing logs, sealing secrets, triggering rollouts. Use when starting a new app, deploying, debugging, or running kubectl/kubeseal commands against the homelab.
---

## Purpose

Generates all boilerplate needed to deploy a new application to the Talos/K8s homelab. Two outputs:

1. **Project side** — `Dockerfile` (and optionally `Dockerfile.migrate`), `.github/workflows/docker-publish.yml`
2. **Homelab side** — `homelab/applications/{name}/` with K8s manifests auto-synced by ArgoCD

The homelab repo is at `/home/coder/workspace/homelab`. Image registry is `ghcr.io/erikandreasklokk`. Domain is `*.erikak.no`.

> **Environment note:** this runs as a pod **inside** the cluster. `kubectl` and `kubeseal` are native binaries and authenticate via the pod's in-cluster ServiceAccount — run them directly, with **no** `wsl -- bash -lc "…"` wrapper and no external kubeconfig. The ServiceAccount has read-all + write on workloads (Deployments/StatefulSets/pods, rollout, logs, exec); it cannot delete namespaces or edit cluster RBAC.

---

## Step 1 — Gather inputs

Ask the user for any of the following that are not already clear from context:

| Input | Default | Notes |
|---|---|---|
| `NAME` | (required) | lowercase slug, hyphens OK — used as namespace, image name, subdomain, K8s resource names |
| `PORT` | `3000` | container port the app listens on |
| `SUBDOMAIN` | `NAME.erikak.no` | full hostname for the HTTPRoute |
| `NEEDS_DB` | no | whether to add a CloudNative-PG PostgreSQL cluster |
| `NEEDS_MIGRATE` | no (yes if NEEDS_DB + Drizzle) | whether to build a separate `Dockerfile.migrate` migration image |

If working inside an existing project directory, infer from `package.json` (Drizzle → NEEDS_MIGRATE=yes, adapter-node → PORT=3000).

---

## Step 2 — Generate project-side files

Write these files into the current project's root (or wherever the user specifies).

### `Dockerfile`

```dockerfile
# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci
COPY . .

# Provide a dummy DATABASE_URL if the build requires it
ENV DATABASE_URL=postgresql://postgres:postgres@localhost:5432/{NAME}

RUN npm run build
RUN npm prune --production

# Production stage
FROM node:20-alpine AS production

WORKDIR /app

RUN addgroup -g 1001 -S nodejs && \
    adduser -S appuser -u 1001

COPY --from=builder --chown=appuser:nodejs /app/build ./build
COPY --from=builder --chown=appuser:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:nodejs /app/package.json ./

USER appuser

EXPOSE {PORT}

ENV NODE_ENV=production
ENV PORT={PORT}
ENV HOST=0.0.0.0

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:{PORT}/health || exit 1

CMD ["node", "build"]
```

> If the project has a `static/` directory, add `COPY --from=builder --chown=appuser:nodejs /app/static ./static` before `USER appuser`.
>
> If the app does not expose a `/health` endpoint, change the HEALTHCHECK path to `/` or omit it.
>
> Remove the `ENV DATABASE_URL` dummy line if the project does not use a database at build time.

### `Dockerfile.migrate` (only if NEEDS_MIGRATE=yes)

```dockerfile
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY drizzle.config.ts ./
COPY src/lib/server/db/schema.ts ./src/lib/server/db/
COPY tsconfig.json ./

CMD ["npx", "drizzle-kit", "push", "--force"]
```

Adjust the `COPY` paths if the schema file is in a different location.

### `.github/workflows/docker-publish.yml`

**Without migrate image** (NEEDS_MIGRATE=no):

```yaml
name: Docker

on:
  push:
    branches: [ "main" ]
    tags: [ 'v*.*.*' ]
  pull_request:
    branches: [ "main" ]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install cosign
        if: github.event_name != 'pull_request'
        uses: sigstore/cosign-installer@59acb6260d9c0ba8f4a2f9d9b48431a222b68e20 #v3.5.0
        with:
          cosign-release: 'v2.2.4'

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@f95db51fddba0c2d1ec667646a06c2ce06100226 # v3.0.0

      - name: Log into registry ${{ env.REGISTRY }}
        if: github.event_name != 'pull_request'
        uses: docker/login-action@343f7c4344506bcbf9b4de18042ae17996df046d # v3.0.0
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract Docker metadata
        id: meta
        uses: docker/metadata-action@96383f45573cb7f253c731d3b3ab81c87ef81934 # v5.0.0
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}

      - name: Build and push Docker image
        id: build-and-push
        uses: docker/build-push-action@0565240e2d4ab88bba5387d719585280857ece09 # v5.0.0
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Sign the published Docker image
        if: ${{ github.event_name != 'pull_request' }}
        env:
          TAGS: ${{ steps.meta.outputs.tags }}
          DIGEST: ${{ steps.build-and-push.outputs.digest }}
        run: echo "${TAGS}" | xargs -I {} cosign sign --yes {}@${DIGEST}
```

**With migrate image** (NEEDS_MIGRATE=yes) — append these steps after the sign step:

```yaml
      - name: Extract Docker metadata for migration image
        id: meta-migrate
        uses: docker/metadata-action@96383f45573cb7f253c731d3b3ab81c87ef81934 # v5.0.0
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}-migrate

      - name: Build and push migration Docker image
        uses: docker/build-push-action@0565240e2d4ab88bba5387d719585280857ece09 # v5.0.0
        with:
          context: .
          file: ./Dockerfile.migrate
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta-migrate.outputs.tags }}
          labels: ${{ steps.meta-migrate.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## Step 3 — Generate homelab manifests

Create `/home/coder/workspace/homelab/applications/{NAME}/` and write the following files. ArgoCD auto-discovers new subdirectories via `applications/application-set.yaml` — no manual `kubectl apply` needed.

### `ns.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: {NAME}
```

### `deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {NAME}
  namespace: {NAME}
  labels:
    app: {NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {NAME}
  template:
    metadata:
      namespace: {NAME}
      labels:
        app: {NAME}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: {NAME}
          image: ghcr.io/erikandreasklokk/{NAME}:main
          imagePullPolicy: Always
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ "ALL" ]
          ports:
            - name: web
              containerPort: {PORT}
          readinessProbe:
            httpGet:
              path: /health
              port: {PORT}
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: {PORT}
            initialDelaySeconds: 15
            periodSeconds: 20
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
```

> If the app does not expose `/health`, change the probe path to `/`.
>
> If the app uses environment variables (e.g. database credentials), add `env:` under the container following the budgeting pattern — reference them from a SealedSecret via `secretKeyRef`.

### `svc.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {NAME}
  namespace: {NAME}
spec:
  type: ClusterIP
  selector:
    app: {NAME}
  ports:
    - name: web
      port: {PORT}
      targetPort: {PORT}
      protocol: TCP
```

### `http-route.yaml`

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {NAME}
  namespace: {NAME}
spec:
  parentRefs:
    - name: external
      namespace: gateway
  hostnames:
    - "{SUBDOMAIN}"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: {NAME}
          port: {PORT}
```

### `kustomization.yaml` (no DB)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ns.yaml
  - deployment.yaml
  - svc.yaml
  - http-route.yaml
```

### Additional files when NEEDS_DB=yes

**`postgresql-cluster.yaml`**

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: {NAME}-postgresql
spec:
  imageName: ghcr.io/tensorchord/cloudnative-pgvecto.rs:16.5-v0.3.0@sha256:be3f025d79aa1b747817f478e07e71be43236e14d00d8a9eb3914146245035ba
  instances: 1

  postgresql:
    parameters:
      timezone: Europe/Oslo

  managed:
    roles:
      - name: {NAME}
        superuser: true
        login: true

  bootstrap:
    initdb:
      database: {NAME}
      owner: {NAME}
      secret:
        name: {NAME}-postgresql-secret

  storage:
    size: 10G
    storageClass: local-path

  monitoring:
    enablePodMonitor: false
```

Adjust `storage.size` to fit the expected data volume.

**`postgresql-sealed-secret.yaml`** — placeholder (must be sealed before committing):

```yaml
# Seal this before committing.
# 1. Generate the plain secret (never commit this):
#    kubectl create secret generic {NAME}-postgresql-secret \
#      --from-literal=postgresql-password=CHANGEME \
#      -n {NAME} --dry-run=client -o yaml > secret.yaml
# 2. Seal it:
#    kubeseal -f secret.yaml -w {NAME}/postgresql-sealed-secret.yaml
# 3. Delete secret.yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: {NAME}-postgresql-secret
  namespace: {NAME}
spec:
  encryptedData: {}
  template:
    metadata:
      name: {NAME}-postgresql-secret
      namespace: {NAME}
```

**`db-init-job.yaml`** (only if NEEDS_MIGRATE=yes):

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {NAME}-db-migrate
  namespace: {NAME}
spec:
  backoffLimit: 4
  ttlSecondsAfterFinished: 120
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: ghcr.io/erikandreasklokk/{NAME}-migrate:main
          imagePullPolicy: Always
          env:
            - name: POSTGRESQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {NAME}-postgresql-secret
                  key: postgresql-password
            - name: DATABASE_URL
              value: "postgresql://{NAME}:$(POSTGRESQL_PASSWORD)@{NAME}-postgresql-rw:5432/{NAME}"
```

**`kustomization.yaml`** (with DB + migrate):

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ns.yaml
  - postgresql-sealed-secret.yaml
  - postgresql-cluster.yaml
  - http-route.yaml
  - deployment.yaml
  - svc.yaml
  - db-init-job.yaml
```

Add `deployment.yaml` env block for DB credentials:

```yaml
          env:
            - name: POSTGRESQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {NAME}-postgresql-secret
                  key: postgresql-password
            - name: DATABASE_URL
              value: "postgresql://{NAME}:$(POSTGRESQL_PASSWORD)@{NAME}-postgresql-rw:5432/{NAME}"
```

---

## Cluster operations (kubectl / kubeseal)

Run `kubectl` and `kubeseal` directly — they use the in-cluster ServiceAccount. Cluster context is the one the pod runs in (Talos, `talos-proxmox-cluster`).

### Deploy a code change to the cluster (after a push to `main`)

Apps run the `main`-tagged image with `imagePullPolicy: Always`. A push to `main` rebuilds and re-pushes that image, but the running pods keep the **old** image — the tag and the homelab YAML are unchanged, so ArgoCD doesn't restart anything. You must roll out manually. End-to-end:

1. **Wait for CI to finish building the new image.** A push triggers (at least) two workflows — `Node.js CI` and `Docker`. Only the **Docker** workflow builds and pushes the image; rolling out before it finishes pulls the *previous* image. Check the repo's Actions via the public API:
   ```bash
   # repo example: ErikAndreasKlokk/Portfolio — match the Docker run to your pushed commit SHA
   curl -s "https://api.github.com/repos/<owner>/<repo>/actions/runs?per_page=5" \
     | jq -r '.workflow_runs[] | "\(.name)\t\(.status)\t\(.conclusion)\t\(.head_sha[0:7])"'
   ```
   Wait until the `Docker` run for your commit SHA shows `status=completed`, `conclusion=success`. (For public repos the unauthenticated API works fine.)
2. **Roll out** (forces a re-pull of `main`):
   ```bash
   kubectl rollout restart deployment/{NAME} -n {NAME}
   kubectl rollout status deployment/{NAME} -n {NAME} --timeout=180s
   ```
3. **Verify** the new pods are fresh and healthy:
   ```bash
   kubectl get pods -n {NAME} -o wide
   kubectl logs -n {NAME} deployment/{NAME} --tail=8
   ```
   Confirm pods have a low AGE, are `1/1 Running`, and the logs show the app listening.

**Exception — DB schema (Drizzle) changes:** the `{NAME}-db-migrate` Job applies those automatically. With `ttlSecondsAfterFinished` set, ArgoCD self-heal recreates the Job after K8s deletes it, so a schema change lands on the next self-heal cycle once the `{NAME}-migrate` image is built — no manual rollout of the Job needed. The app Deployment still needs the manual rollout above to pick up new app code.

### Common commands

**Check rollout status after a push to main:**
```bash
kubectl rollout status deployment/{NAME} -n {NAME}
```

**Watch pods come up:**
```bash
kubectl get pods -n {NAME} -w
```

**Tail logs:**
```bash
kubectl logs -n {NAME} deployment/{NAME} --follow
```

**Force a re-pull of the image (manual rollout trigger):**
```bash
kubectl rollout restart deployment/{NAME} -n {NAME}
```

**Check ArgoCD sync status:**
```bash
kubectl get application {NAME} -n argocd -o wide
```

**Seal a secret for a new app** (write straight into the homelab dir, then discard the plaintext):
```bash
kubectl create secret generic {NAME}-postgresql-secret \
  --from-literal=postgresql-password=YOURPASSWORD \
  -n {NAME} --dry-run=client -o yaml > /tmp/secret.yaml

kubeseal -f /tmp/secret.yaml -w \
  /home/coder/workspace/homelab/applications/{NAME}/postgresql-sealed-secret.yaml

rm /tmp/secret.yaml
```

**Seal an arbitrary secret (non-database):**
```bash
kubectl create secret generic {SECRET-NAME} \
  --from-literal=key=VALUE \
  -n {NAME} --dry-run=client -o yaml \
  | kubeseal -o yaml \
  > /home/coder/workspace/homelab/applications/{NAME}/{SECRET-NAME}.yaml
```

**Restart the ArgoCD application controller** (if the UI shows errors after a new app is added):
```bash
kubectl -n argocd rollout restart statefulset argocd-application-controller
```

---

## Step 4 — Final checklist

After generating all files, tell the user:

- [ ] Replace `{NAME}`, `{PORT}`, `{SUBDOMAIN}` everywhere if not already done
- [ ] `Dockerfile` — verify the build command, remove dummy `DATABASE_URL` if no DB
- [ ] If NEEDS_DB: seal the PostgreSQL secret with `kubeseal` before committing `postgresql-sealed-secret.yaml`
- [ ] Push the project repo to `github.com/ErikAndreasKlokk/{NAME}` so the CI workflow and image name resolve correctly
- [ ] After the first image is pushed, ArgoCD will auto-sync the app from `homelab/applications/{NAME}/` — no manual `kubectl apply` needed
- [ ] A push to `main` rebuilds and re-pushes the `main`-tagged image, but does **not** redeploy on its own — the running pod keeps the old image because the tag (and the homelab YAML) is unchanged. To pick up the new image, trigger a rollout manually: `kubectl rollout restart deployment/{NAME} -n {NAME}` (`imagePullPolicy: Always` then pulls the latest `main`). One-shot migrate Jobs (`{NAME}-db-migrate`) are the exception — with `ttlSecondsAfterFinished` set, ArgoCD self-heal recreates the Job after K8s deletes it, so schema changes re-apply automatically on the next cycle.
