#!/usr/bin/env bash
#
# teardown.sh
# Deletes the kind cluster and optionally stops the local Docker registry.
#
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-durag-local}"
REG_NAME="${REG_NAME:-kind-registry}"
DELETE_REGISTRY="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --delete-registry)
            DELETE_REGISTRY="true"
            shift 1
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --name <cluster-name>   Cluster name to delete (default: durag-local)"
            echo "  --delete-registry       Also remove the local registry container (kind-registry)"
            echo "  --help, -h              Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=== [durag / day-0] Tearing down kind cluster '${CLUSTER_NAME}' ==="

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    kind delete cluster --name "${CLUSTER_NAME}"
    echo "[+] Kind cluster '${CLUSTER_NAME}' deleted."
else
    echo "[!] Kind cluster '${CLUSTER_NAME}' not found."
fi

if [ "${DELETE_REGISTRY}" = "true" ]; then
    if docker inspect "${REG_NAME}" >/dev/null 2>&1; then
        echo "[*] Removing registry container '${REG_NAME}'..."
        docker rm -f "${REG_NAME}"
        echo "[+] Registry container removed."
    else
        echo "[!] Registry container '${REG_NAME}' not found."
    fi
else
    echo "[i] Local registry '${REG_NAME}' preserved. Pass '--delete-registry' if you want to remove it."
fi

echo "=== [durag / day-0] Teardown complete ==="
