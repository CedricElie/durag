#!/usr/bin/env bash
#
# bootstrap.sh
# Bootstraps a local kind Kubernetes cluster with a local container registry.
# Fully compatible with Linux and macOS (Darwin, Intel & Apple Silicon).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-durag-local}"
REG_NAME="${REG_NAME:-kind-registry}"
REG_PORT="${REG_PORT:-5001}"
HTTP_PORT="${HTTP_PORT:-8088}"
HTTPS_PORT="${HTTPS_PORT:-8443}"
BASE_CONFIG="${SCRIPT_DIR}/kind-config.yaml"
WITH_INGRESS="${WITH_INGRESS:-false}"

# Parse command line flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --http-port)
            HTTP_PORT="$2"
            shift 2
            ;;
        --https-port)
            HTTPS_PORT="$2"
            shift 2
            ;;
        --with-ingress)
            WITH_INGRESS="true"
            shift 1
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --name <cluster-name>   Set the kind cluster name (default: durag-local)"
            echo "  --http-port <port>      Host port to map to ingress HTTP port 80 (default: 8088)"
            echo "  --https-port <port>     Host port to map to ingress HTTPS port 443 (default: 8443)"
            echo "  --with-ingress          Deploy ingress-nginx controller with kind host port bindings"
            echo "  --help, -h              Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "======================================================"
echo "    durag Day-0: Bootstrapping Local kind Cluster     "
echo "    OS:         $(uname -s) ($(uname -m))"
echo "    Cluster:    ${CLUSTER_NAME}"
echo "    Registry:   localhost:${REG_PORT} (${REG_NAME})"
echo "    Ingress:    http://localhost:${HTTP_PORT} / https://localhost:${HTTPS_PORT}"
echo "======================================================"

# 1. Run prerequisite verification
"${SCRIPT_DIR}/install-prereqs.sh"

# Ensure ~/.local/bin is in PATH for this session if tools were installed there
if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
    export PATH="${HOME}/.local/bin:${PATH}"
fi

# 2. Check if kind cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "[!] Cluster '${CLUSTER_NAME}' already exists."
    echo "    To delete and recreate it, run: ${SCRIPT_DIR}/teardown.sh"
    echo "    Switching context to kind-${CLUSTER_NAME}..."
    kubectl config use-context "kind-${CLUSTER_NAME}"
    exit 0
fi

# 3. Create local Docker registry container if not already running
echo "[*] Ensuring local container registry '${REG_NAME}' is running on port ${REG_PORT}..."
if [ "$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || true)" != 'true' ]; then
    # If container exists but stopped, remove it before running fresh
    if docker inspect "${REG_NAME}" >/dev/null 2>&1; then
        docker rm -f "${REG_NAME}"
    fi
    docker run -d \
        --restart=always \
        -p "127.0.0.1:${REG_PORT}:5000" \
        --network bridge \
        --name "${REG_NAME}" \
        registry:2
    echo "[+] Local registry started at localhost:${REG_PORT}"
else
    echo "[+] Local registry '${REG_NAME}' is already running at localhost:${REG_PORT}"
fi

# 4. Generate rendered Kind config with chosen host ports
# (POSIX and BSD mktemp compliant: template must end with XXXXXX)
RENDERED_CONFIG="$(mktemp "${TMPDIR:-/tmp}/kind-config-XXXXXX")"
trap 'rm -f "${RENDERED_CONFIG}"' EXIT

sed -e "s/hostPort: 8088/hostPort: ${HTTP_PORT}/" \
    -e "s/hostPort: 8443/hostPort: ${HTTPS_PORT}/" \
    "${BASE_CONFIG}" > "${RENDERED_CONFIG}"

# 5. Create Kind cluster using the config
echo "[*] Creating kind cluster '${CLUSTER_NAME}' with HTTP hostPort=${HTTP_PORT}, HTTPS hostPort=${HTTPS_PORT}..."
kind create cluster --name "${CLUSTER_NAME}" --config "${RENDERED_CONFIG}"

# Label worker nodes with standard node-role.kubernetes.io/worker
kubectl label nodes -l durag.io/node-type node-role.kubernetes.io/worker="" --overwrite >/dev/null 2>&1 || true

# 6. Connect local registry to the kind network
echo "[*] Connecting registry container to kind network..."
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${REG_NAME}" 2>/dev/null)" = 'null' ]; then
    docker network connect "kind" "${REG_NAME}"
    echo "[+] Registry connected to 'kind' network"
else
    echo "[+] Registry already connected to 'kind' network"
fi

# 7. Document the local registry in kube-system (Kubernetes KEP-1755 standard)
echo "[*] Documenting local registry in kube-system/local-registry-hosting..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-system
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

# 8. Optionally install Ingress NGINX controller for Kind
if [ "${WITH_INGRESS}" = "true" ]; then
    echo "[*] Deploying ingress-nginx controller for kind..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    echo "[*] Waiting for ingress-nginx controller pod to be ready (timeout 120s)..."
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=120s || echo "[!] Notice: Ingress pod is still starting up in the background."
fi

# 9. Cluster Status Summary
echo ""
echo "======================================================"
echo "    Kind Cluster Bootstrap Completed Successfully!   "
echo "======================================================"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
echo ""
echo "Nodes in cluster:"
kubectl get nodes -o wide
echo ""
echo "Local container registry: localhost:${REG_PORT}"
echo "To push images to the local registry for durag:"
echo "  docker build -t localhost:${REG_PORT}/durag:<tag> ."
echo "  docker push localhost:${REG_PORT}/durag:<tag>"
echo ""
echo "Ingress host mappings:"
echo "  HTTP:  http://localhost:${HTTP_PORT}"
echo "  HTTPS: https://localhost:${HTTPS_PORT}"
echo ""
echo "Kubectl context set to: kind-${CLUSTER_NAME}"
