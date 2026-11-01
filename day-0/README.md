# Day-0: Local Kubernetes (kind) Cluster Bootstrap

This folder contains the Day-0 scripts and declarative configuration to install, configure, and bootstrap a local **Kubernetes in Docker (kind)** cluster tailored for the **durag** project, fulfilling tasks `0.1` and `0.3` of [Phase 0 in the WBS](../docs/wbs.md#phase-0--project-bootstrap-local-kubernetes-environment-and-helm-scaffolding).

The setup supports **Linux**, **macOS** (Intel `x86_64` and Apple Silicon `arm64`), and **Windows** through Windows PowerShell 5.1 or PowerShell 7.

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
* **Windows:**
  * [Windows Package Manager (`winget`)](https://learn.microsoft.com/windows/package-manager/winget/) for automatic Docker Desktop installation. Docker Desktop installation may require administrator approval, WSL 2, virtualization support, or a restart.
  * Windows PowerShell 5.1 or PowerShell 7.

*Note: The prerequisite scripts check for Docker, `kubectl`, `helm`, and `kind`. On Windows, missing Docker Desktop is installed through `winget`, then started and checked for engine readiness. Missing `kubectl`, Helm, and kind are downloaded to `$HOME\.local\bin`, which is added to PATH for the current PowerShell session. Docker Desktop installation can require elevation, WSL 2, virtualization support, or a restart; the bootstrap reports an error if Windows needs setup before Docker can start. Automatic `kind` installation on Windows currently requires x64; on Windows ARM64, install `kind` separately and make it available in PATH or `$HOME\.local\bin`.*

---

## Files

| File | Description |
|---|---|
| [`kind-config.yaml`](./kind-config.yaml) | Declarative cluster topology with node roles, labels, port mappings, and containerd registry patches. |
| [`install-prereqs.sh`](./install-prereqs.sh) | Cross-platform installer for Linux & macOS (Intel & Apple Silicon) for Docker, kubectl, Helm, and kind. |
| [`bootstrap.sh`](./bootstrap.sh) | End-to-end bootstrap: checks prereqs, spins up registry, creates cluster, wires network, and verifies nodes. |
| [`install-prereqs.ps1`](./install-prereqs.ps1) | Windows PowerShell prerequisite checker and installer for Docker, kubectl, Helm, and kind. |
| [`bootstrap.ps1`](./bootstrap.ps1) | Windows PowerShell end-to-end bootstrap for the local registry and kind cluster. |
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

### Windows (PowerShell)

Run these commands from the repository root in PowerShell. The prerequisite script installs Docker Desktop through `winget` when it is missing, then starts it and waits for the engine:
```powershell
.\day-0\install-prereqs.ps1
.\day-0\bootstrap.ps1
```

Customize the host ports or deploy the NGINX Ingress controller:
```powershell
.\day-0\bootstrap.ps1 -HttpPort 8088 -HttpsPort 8443 -WithIngress
```

`-Name`, `-HttpPort`, and `-HttpsPort` customize the cluster name and ports. The PowerShell scripts honor the same `CLUSTER_NAME`, `REG_NAME`, `REG_PORT`, `HTTP_PORT`, `HTTPS_PORT`, `WITH_INGRESS`, and `KIND_VERSION` environment variables as their shell counterparts.

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
