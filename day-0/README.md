# Day-0: Local Kubernetes (kind) Cluster Bootstrap

This folder contains the Day-0 scripts and declarative configuration to install, configure, and bootstrap a local **Kubernetes in Docker (kind)** cluster tailored for the **durag** project, fulfilling tasks `0.1` and `0.3` of [Phase 0 in the WBS](../docs/wbs.md#phase-0--project-bootstrap-local-kubernetes-environment-and-helm-scaffolding).

The setup is **fully cross-platform** and supports both **Linux** and **macOS** (Intel `x86_64` and Apple Silicon `arm64`).

---

## What is Provisioned

1. **kind Cluster (`durag-local`):**
   * **1 Control Plane Node:** Configured with `ingress-ready=true` label and host port mappings for `8088` (HTTP) and `8443` (HTTPS) to avoid collisions with other host services.
   * **1 Worker Node (`durag.io/node-type: compute`):** Designated for stateless API, query, and worker pods.
   * **1 Worker Node (`durag.io/node-type: storage`):** Designated for stateful backing services (MinIO, PostgreSQL / pgvector).
2. **Local Container Registry (`kind-registry`):**
   * Runs a local Docker container registry on `localhost:5001`.
   * Automatically wired into the `kind` Docker network.
   * Configured via containerd mirrors so nodes can resolve `localhost:5001` images directly.
   * Advertised inside the cluster via `kube-system/local-registry-hosting` (KEP-1755).
3. **Optional Ingress Controller:**
   * Support for installing `ingress-nginx` pre-configured for kind port forwarding (`--with-ingress`).

---

## Prerequisites

Before running the scripts:

* **Linux:**
  * Docker installed and running with permissions to access `/var/run/docker.sock` without `sudo`.
* **macOS:**
  * [Docker Desktop](https://www.docker.com/products/docker-desktop), [OrbStack](https://orbstack.dev/), or [Colima](https://github.com/abiosoft/colima) running.
  * (Optional) [Homebrew](https://brew.sh) — if present, `install-prereqs.sh` will leverage `brew` to install CLI tools.

*Note: The bootstrap script automatically checks for `kubectl`, `helm`, and `kind`. If any tool is missing, it will automatically install the correct binary for your OS (`linux` or `darwin`) and architecture (`amd64` or `arm64`) into `~/.local/bin` (or via `brew`).*

---

## Files

| File | Description |
|---|---|
| [`kind-config.yaml`](./kind-config.yaml) | Declarative cluster topology with node roles, labels, port mappings, and containerd registry patches. |
| [`install-prereqs.sh`](./install-prereqs.sh) | Cross-platform installer for Linux & macOS (Intel & Apple Silicon) for Docker, kubectl, Helm, and kind. |
| [`bootstrap.sh`](./bootstrap.sh) | End-to-end bootstrap: checks prereqs, spins up registry, creates cluster, wires network, and verifies nodes. |
| [`teardown.sh`](./teardown.sh) | Deletes the cluster and optionally removes the local registry. |

---

## Quickstart

### 1. Make scripts executable
```bash
chmod +x day-0/*.sh
```

### 2. Bootstrap the cluster
To create the cluster with local registry:
```bash
./day-0/bootstrap.sh
```

To customize host ports or enable the NGINX Ingress controller:
```bash
./day-0/bootstrap.sh --http-port 8088 --https-port 8443 --with-ingress
```

### 3. Verify the cluster
```bash
kubectl get nodes -o wide
kubectl cluster-info
```

### 4. Build and push images locally
To build and use custom container images without needing Docker Hub / external credentials:
```bash
docker build -t localhost:5001/durag:dev .
docker push localhost:5001/durag:dev
```
Inside Kubernetes manifests or Helm charts, reference:
```yaml
image:
  repository: localhost:5001/durag
  tag: dev
  pullPolicy: IfNotPresent
```

---

## Teardown

To delete the kind cluster while keeping the local registry container intact (saves pulled base images):
```bash
./day-0/teardown.sh
```

To delete both the cluster and the local registry:
```bash
./day-0/teardown.sh --delete-registry
```
