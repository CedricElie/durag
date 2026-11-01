# Operator Guide: Manual Installation, Deployment, and Operations

This guide provides step-by-step, copy-pasteable instructions for a Linux system administrator to install, deploy, and operate **durag** from scratch on a Linux host (or macOS) without requiring automated AI tooling.

Every step includes the exact terminal command to run and the expected output to verify success.

---

## Table of Contents

1. [Prerequisites & System Requirements](#1-prerequisites--system-requirements)
2. [Step 1: Host Preparation and Repository Setup](#step-1-host-preparation-and-repository-setup)
3. [Step 2: Bootstrap the Local Kubernetes Cluster & Container Registry](#step-2-bootstrap-the-local-kubernetes-cluster--container-registry)
4. [Step 3: Two-Tier Validation Strategy (Local & CI)](#step-3-two-tier-validation-strategy-local--ci)
5. [Step 4: Build and Publish the durag Container Image](#step-4-build-and-publish-the-durag-container-image)
6. [Step 5: Deploy durag with Helm](#step-5-deploy-durag-with-helm)
7. [Step 6: Verify the Deployment](#step-6-verify-the-deployment)
8. [Step 7: Day-2 Operations and Maintenance](#step-7-day-2-operations-and-maintenance)
9. [Step 8: Pre-Push Verification Checklist for Chart Updates](#step-8-pre-push-verification-checklist-for-chart-updates)
10. [Step 9: Troubleshooting Common Issues](#step-9-troubleshooting-common-issues)
11. [Step 10: Teardown & Clean Up](#step-10-teardown--clean-up)

---

## 1. Prerequisites & System Requirements

### Hardware Requirements
* **CPU:** 4+ vCPUs recommended
* **Memory:** 8 GB RAM minimum (16 GB recommended for running local models & stateful backing services)
* **Disk:** 20 GB free space (Docker storage and MinIO PVC volume cache)

### Software Requirements
* **Operating System:** Linux (Rocky Linux 9+, Ubuntu 22.04+, Debian 12+, RHEL 9+) or macOS (with Docker Desktop / OrbStack / Colima).
* **Docker Engine:** Version 24.0+ installed and running.
* **kubectl:** Version 1.28+.
* **Helm:** Version 3.12+.
* **kind:** Version 0.20+.
* **Python:** Version 3.9+ with `pip`.

---

## Step 1: Host Preparation and Repository Setup

### 1.1 Verify Docker Access
Ensure Docker is installed and the current user has permission to interact with the Docker socket without `sudo`:

```bash
docker info --format 'Docker Version: {{.ServerVersion}}'
```

*Expected output:*
```text
Docker Version: 29.x.x
```

> **SysAdmin Note:** If you get a permission denied error on `/var/run/docker.sock`, add your user to the `docker` group, reload group membership, and re-test:
> ```bash
> sudo usermod -aG docker $USER
> newgrp docker
> ```

### 1.2 Clone the Repository
Clone the repository and enter the workspace directory:

```bash
git clone https://github.com/CedricElie/durag.git
cd durag
```

### 1.3 Install Required CLI Binaries (Automated or Manual)

You can run the automated prerequisite installer:
```bash
chmod +x day-0/*.sh scripts/*.sh
./day-0/install-prereqs.sh
```

**Or install missing binaries manually:**

* **Install `kind` (if missing):**
  ```bash
  mkdir -p ~/.local/bin
  curl -Lo ~/.local/bin/kind https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-amd64
  chmod +x ~/.local/bin/kind
  export PATH="${HOME}/.local/bin:${PATH}"
  ```

* **Install `kubectl` (if missing):**
  ```bash
  curl -Lo ~/.local/bin/kubectl https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
  chmod +x ~/.local/bin/kubectl
  ```

* **Install `helm` (if missing):**
  ```bash
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | USE_SUDO=false HELM_INSTALL_DIR=~/.local/bin bash
  ```

Verify all required tools are present:
```bash
docker --version && kind version && kubectl version --client && helm version --short
```

---

## Step 2: Bootstrap the Local Kubernetes Cluster & Container Registry

The cluster topology uses a control plane with ingress host mappings and dedicated worker nodes for compute and storage.

### 2.1 Run the Bootstrap Script
Run the Day-0 bootstrap script:

```bash
./day-0/bootstrap.sh
```

*(Optional) If you want to automatically deploy the NGINX Ingress Controller:*
```bash
./day-0/bootstrap.sh --with-ingress
```

### 2.2 What the Bootstrap Script Does Under the Hood:
1. Starts a local Docker container registry container named `kind-registry` listening on `localhost:5001`.
2. Creates a 3-node `kind` cluster named `durag-local` using `day-0/kind-config.yaml`.
3. Maps host ports `8088` (HTTP) and `8443` (HTTPS) to the control plane to avoid conflicting with host web servers.
4. Connects `kind-registry` to the `kind` Docker bridge network.
5. Applies a standard KEP-1755 ConfigMap (`local-registry-hosting`) to `kube-system` so cluster components discover the local registry.
6. Labels worker nodes (`durag.io/node-type: compute` and `durag.io/node-type: storage`).

### 2.3 Verify the Cluster State
Verify cluster nodes and their readiness:

```bash
kubectl get nodes -o wide -L durag.io/node-type
```

*Expected output:*
```text
NAME                        STATUS   ROLES           AGE   VERSION   NODE-TYPE
durag-local-control-plane   Ready    control-plane   1m    v1.37.0   
durag-local-worker          Ready    worker          1m    v1.37.0   compute
durag-local-worker2         Ready    worker          1m    v1.37.0   storage
```

Verify the local registry container is running:
```bash
docker ps --filter "name=kind-registry"
```

---

## Step 3: Two-Tier Validation Strategy (Local & CI)

To maintain rapid development velocity while guaranteeing release stability, `durag` uses a **Two-Tier Validation Strategy**:

| Tier | Environment | Scope | Trigger | Execution Time |
|---|---|---|---|---|
| **Tier 1 (Inner Loop)** | Local Developer Machine | Fast Python tests, Helm lint, and template sanity check | Run manually (`./scripts/validate.sh`) or pre-commit hook | **< 3 seconds** |
| **Tier 2 (Outer Loop)** | GitHub Actions | Clean-room clean build, test matrix, multi-stage Docker build, Helm validation | Pull Request to `main` | **~ 2 minutes** |

### 3.1 Running Tier-1 Local Pre-Flight Checks
Before staging or committing code, run the local validation runner:

```bash
./scripts/validate.sh
```

*Expected output:*
```text
==========================================================
    durag: Tier-1 Local Pre-Flight Validation             
==========================================================
[*] Running Python unit tests... PASSED
[*] Running Helm lint (base values)... PASSED
[*] Running Helm lint (local values)... PASSED
[*] Testing Helm template rendering... PASSED
==========================================================
    All Tier-1 checks passed successfully in 0s!         
    Safe to commit and push.                              
==========================================================
```

### 3.2 Advanced Validation Options
You can pass flags to validate additional components locally:

```bash
# Validate including live Kind cluster connectivity check
./scripts/validate.sh --cluster

# Validate including Docker multi-stage build check
./scripts/validate.sh --docker

# Run complete validation (Python, Helm, Docker, and Cluster)
./scripts/validate.sh --all
```

### 3.3 (Optional) Install Automatic Git Pre-Commit Hook
To guarantee that broken code or invalid Helm templates can never be committed:

```bash
./scripts/validate.sh --install-hook
```

---

## Step 4: Build and Publish the durag Container Image

### 4.1 Local Python Verification
To test and install the Python CLI locally:

```bash
python3 -m unittest discover tests
python3 -m pip install -e . --no-deps
durag --version
```

*Expected output:*
```text
durag 0.1.0
```

### 4.2 Build the Multi-Stage Docker Image
Build the container image using the project's production `Dockerfile`:

```bash
docker build -t localhost:5001/durag:0.1.0 .
```

### 4.3 Push Image to Local Registry
Push the built image to the local `kind-registry`:

```bash
docker push localhost:5001/durag:0.1.0
```

*Expected output:*
```text
The push refers to repository [localhost:5001/durag]
...
0.1.0: digest: sha256:... size: 856
```

---

## Step 5: Deploy durag with Helm

The infrastructure and application components are packaged as a primary Helm chart under `charts/durag`.

### 5.1 Lint the Helm Chart
Ensure chart syntax, values, and templates are error-free:

```bash
helm lint ./charts/durag -f ./charts/durag/values-local.yaml
```

*Expected output:*
```text
==> Linting ./charts/durag
1 chart(s) linted, 0 chart(s) failed
```

### 5.2 Dry-Run Template Rendering (Sanity Check)
Preview the rendered Kubernetes manifests:

```bash
helm template durag ./charts/durag -f ./charts/durag/values-local.yaml
```

### 5.3 Install or Upgrade the Release
Deploy the chart to the `durag` namespace:

```bash
helm upgrade --install durag ./charts/durag \
  --namespace durag \
  --create-namespace \
  -f ./charts/durag/values-local.yaml
```

*Expected output:*
```text
Release "durag" has been upgraded. Happy Helming!
NAME: durag
NAMESPACE: durag
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

---

## Step 6: Verify the Deployment

### 6.1 Check Helm Release Status
```bash
helm list -n durag
```

### 6.2 Inspect Created Namespace Resources
Check the deployed ServiceAccount, ConfigMap, ResourceQuota, and LimitRange:

```bash
kubectl get configmap,serviceaccount,resourcequota,limitrange -n durag
```

*Expected output:*
```text
NAME                     DATA   AGE
configmap/durag-config   5      1m

NAME                     AGE
serviceaccount/durag     1m

NAME                        REQUEST                                                 LIMIT
resourcequota/durag-quota   pods: 0/30, requests.cpu: 0/4, requests.memory: 0/8Gi   limits.cpu: 0/8, limits.memory: 0/16Gi

NAME                      CREATED AT
limitrange/durag-limits   2026-11-01T...
```

### 6.3 Test Running a Container from the Local Registry
Verify that Kubernetes nodes can pull and run the `localhost:5001/durag:0.1.0` image:

```bash
kubectl run durag-smoke-test \
  --image=localhost:5001/durag:0.1.0 \
  --restart=Never \
  -n durag \
  --command -- durag info
```

Check the pod execution logs:
```bash
kubectl logs durag-smoke-test -n durag
```

*Expected output:*
```text
durag version: 0.1.0
Status: Phase 0 bootstrap initialized
```

Clean up the test pod:
```bash
kubectl delete pod durag-smoke-test -n durag
```

---

## Step 7: Day-2 Operations and Maintenance

### 7.1 Inspect Application Configuration
To see the runtime environment configuration injected by Helm:
```bash
kubectl describe configmap durag-config -n durag
```

### 7.2 Modifying Configuration Values
To modify configurations (e.g., change `LOG_LEVEL` or adjust resource quotas), update `charts/durag/values-local.yaml` or pass parameters via `--set`:

```bash
helm upgrade durag ./charts/durag \
  --namespace durag \
  -f ./charts/durag/values-local.yaml \
  --set config.logLevel="INFO"
```

### 7.3 Checking Resource Usage against Quotas
Monitor namespace quota consumption:
```bash
kubectl describe resourcequota durag-quota -n durag
```

---

## Step 8: Pre-Push Verification Checklist for Chart Updates

Whenever you modify any file in `charts/durag/` (`Chart.yaml`, templates, or value files), **always execute this 6-step checklist before pushing to git**. This ensures your changes will pass remote CI and will not break running clusters.

```
[Edit Chart Files] 
       │
       ▼
1. Run Tier-1 Validator      ──►  ./scripts/validate.sh
       │
       ▼
2. Lint All Value Profiles   ──►  helm lint base & values-local
       │
       ▼
3. Template Dry-Run & Parse  ──►  helm template ... | kubectl apply --dry-run=client
       │
       ▼
4. Server Dry-Run on Cluster ──►  helm upgrade ... --dry-run=server
       │
       ▼
5. Live Local Upgrade Test   ──►  helm upgrade ... (verify pod/resource health)
       │
       ▼
6. Git Review & Push         ──►  git diff charts/durag && git push
```

### 8.1 Step 1: Run Tier-1 Local Pre-Flight Validator
Execute the local runner to verify Python tests and basic Helm template validity in under 1 second:

```bash
./scripts/validate.sh
```

### 8.2 Step 2: Lint Across All Supported Value Profiles
Verify that the chart is valid under both default values and environment-specific overrides:

```bash
# Lint default base values
helm lint ./charts/durag

# Lint local development values
helm lint ./charts/durag -f ./charts/durag/values-local.yaml
```

*Expected output:* `1 chart(s) linted, 0 chart(s) failed`.

### 8.3 Step 3: Dry-Run Template Rendering and Kubernetes Client Validation
Render the chart with debug output and pipe it through `kubectl --dry-run=client` to ensure all generated YAML manifests are structurally valid:

```bash
helm template durag ./charts/durag -f ./charts/durag/values-local.yaml --debug | kubectl apply --dry-run=client -f -
```

*Expected output:*
```text
serviceaccount/durag configured (dry run)
configmap/durag-config configured (dry run)
resourcequota/durag-quota configured (dry run)
limitrange/durag-limits configured (dry run)
```

> **SysAdmin Tip:** If template variables are missing or a Go template block has incorrect indentation, this command will catch the exact line number immediately.

### 8.4 Step 4: Server-Side Dry-Run Against Live Cluster
Validate how the actual Kubernetes API server interprets your changes against active admission controllers and schema definitions, without modifying cluster state:

```bash
helm upgrade durag ./charts/durag \
  --namespace durag \
  -f ./charts/durag/values-local.yaml \
  --dry-run=server
```

### 8.5 Step 5: Live Upgrade & Cluster Health Check
Apply the chart upgrade to your local `kind` cluster and verify that resources deploy cleanly:

```bash
# Apply upgrade
helm upgrade durag ./charts/durag \
  --namespace durag \
  -f ./charts/durag/values-local.yaml

# Verify release revision and resources
helm status durag -n durag
kubectl get all,configmap,resourcequota,limitrange -n durag
```

Ensure no pods enter `CrashLoopBackOff`, `ImagePullBackOff`, or `OOMKilled`.

### 8.6 Step 6: Git Diff Review and Safe Push
Check the exact diff in `charts/durag` to confirm only intended changes are staged, with no secrets or accidental edits:

```bash
git diff charts/durag
git status
git add charts/durag/
git commit -m "fix(helm): <describe your chart change>"
git push origin <your-branch>
```

---

## Step 9: Troubleshooting Common Issues

### Issue 1: "Bind for 0.0.0.0:80 failed: port is already allocated"
* **Cause:** Another service on the Linux host (e.g., Apache, NGINX, or a Docker web server) is already listening on port 80.
* **Fix:** The bootstrap script defaults to non-conflicting host ports `8088` and `8443`. If `8088` is also taken, customize the host ports:
  ```bash
  ./day-0/bootstrap.sh --http-port 8090 --https-port 8444
  ```

### Issue 2: Pod fails with `ErrImagePull` or `ImagePullBackOff` for `localhost:5001`
* **Cause:** The `kind-registry` container is either stopped or disconnected from the `kind` Docker network.
* **Fix:** Reconnect the registry and restart it:
  ```bash
  docker start kind-registry || true
  docker network connect kind kind-registry || true
  ```

### Issue 3: `kubectl` commands fail with connection refused
* **Cause:** The active context is not pointing to the `kind-durag-local` cluster.
* **Fix:** Switch the active kubeconfig context:
  ```bash
  kubectl config use-context kind-durag-local
  ```

---

## Step 10: Teardown & Clean Up

### 10.1 Uninstall the Helm Release
To remove the application and namespace resources:

```bash
helm uninstall durag -n durag
kubectl delete namespace durag
```

### 10.2 Delete the Kind Cluster
To destroy the local Kubernetes cluster while keeping the local registry container (so cached images are preserved):

```bash
./day-0/teardown.sh
```

To destroy **both** the cluster and the local registry container:

```bash
./day-0/teardown.sh --delete-registry
```
