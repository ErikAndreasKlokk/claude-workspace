# code-server + Claude Code + cluster tooling, for the homelab "code from my phone" pod.
# Base image ships code-server, the `coder` user (uid 1000), the entrypoint and
# password auth. We add Node 20, the Claude Code CLI, kubectl and kubeseal.
FROM codercom/code-server:4.126.0

USER root

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git jq wget gnupg \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 (NodeSource) — runs Claude Code and the projects' npm scripts
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# kubectl (pinned — keep within one minor of the cluster's server version, v1.33.x)
ARG KUBECTL_VERSION=v1.33.1
RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
        -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# kubeseal (matches the cluster's sealed-secrets controller, v0.30.x)
ARG KUBESEAL_VERSION=0.30.0
RUN curl -fsSL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" \
        | tar -xz -C /usr/local/bin kubeseal \
    && chmod +x /usr/local/bin/kubeseal

USER coder

# code-server listens here; the Service targets it.
EXPOSE 8080
