#!/usr/bin/env bash
#
# install-prereqs.sh
# Verifies system prerequisites (Docker, kubectl, helm) and installs kind if needed.
# Compatible with both Linux and macOS (Intel and Apple Silicon).
#
set -euo pipefail

KIND_VERSION="${KIND_VERSION:-v0.33.0}"
BIN_DIR="${HOME}/.local/bin"

# 0. OS and Architecture Detection
UNAME_S="$(uname -s)"
case "${UNAME_S}" in
    Linux*)  OS="linux" ;;
    Darwin*) OS="darwin" ;;
    *)       echo "[-] Unsupported operating system: ${UNAME_S}"; exit 1 ;;
esac

UNAME_M="$(uname -m)"
case "${UNAME_M}" in
    x86_64)        ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)             echo "[-] Unsupported architecture: ${UNAME_M}"; exit 1 ;;
esac

echo "=== [durag / day-0] Checking prerequisites (${OS}/${ARCH}) ==="

# 1. Docker check
if ! command -v docker >/dev/null 2>&1; then
    echo "[-] Error: docker CLI is not installed."
    if [ "${OS}" = "darwin" ]; then
        echo "    Install Docker Desktop (https://www.docker.com/products/docker-desktop), OrbStack, or Colima ('brew install colima docker')."
    else
        echo "    Install Docker via your distribution's package manager (e.g. apt, dnf)."
    fi
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "[-] Error: Docker daemon is not running or current user does not have permission to access the Docker socket."
    if [ "${OS}" = "darwin" ]; then
        echo "    Hint: Launch Docker Desktop, OrbStack, or start Colima ('colima start')."
    else
        echo "    Hint: Run 'sudo usermod -aG docker $USER' and restart your session, or ensure systemctl is running docker."
    fi
    exit 1
fi
echo "[+] Docker is operational ($(docker --version))"

# 2. kubectl check
if ! command -v kubectl >/dev/null 2>&1; then
    echo "[!] Warning: kubectl is not found in PATH."
    if [ "${OS}" = "darwin" ] && command -v brew >/dev/null 2>&1; then
        echo "[*] Installing kubectl via Homebrew..."
        brew install kubernetes-cli
    else
        echo "    Installing kubectl to ${BIN_DIR}..."
        mkdir -p "${BIN_DIR}"
        KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
        curl -Lo "${BIN_DIR}/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
        chmod +x "${BIN_DIR}/kubectl"
        echo "[+] kubectl ${KUBECTL_VERSION} installed to ${BIN_DIR}/kubectl"
    fi
else
    K8S_CLIENT_VER="$(kubectl version --client 2>/dev/null | grep -i 'Client Version' || echo 'installed')"
    echo "[+] kubectl is available (${K8S_CLIENT_VER})"
fi

# 3. Helm check
if ! command -v helm >/dev/null 2>&1; then
    echo "[!] Warning: helm is not found in PATH."
    if [ "${OS}" = "darwin" ] && command -v brew >/dev/null 2>&1; then
        echo "[*] Installing Helm via Homebrew..."
        brew install helm
    else
        echo "    Installing helm..."
        mkdir -p "${BIN_DIR}"
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | USE_SUDO=false HELM_INSTALL_DIR="${BIN_DIR}" bash
        echo "[+] Helm installed to ${BIN_DIR}/helm"
    fi
else
    echo "[+] Helm is available ($(helm version --short))"
fi

# 4. kind installation
if ! command -v kind >/dev/null 2>&1; then
    echo "[*] kind not found in PATH."
    if [ "${OS}" = "darwin" ] && command -v brew >/dev/null 2>&1; then
        echo "[*] Installing kind via Homebrew..."
        brew install kind
    else
        echo "[*] Downloading kind ${KIND_VERSION} for ${OS}/${ARCH} to ${BIN_DIR}..."
        mkdir -p "${BIN_DIR}"
        KIND_URL="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS}-${ARCH}"
        echo "[*] Fetching from ${KIND_URL}..."
        curl -Lo "${BIN_DIR}/kind" "${KIND_URL}"
        chmod +x "${BIN_DIR}/kind"
    fi

    # Ensure BIN_DIR is in PATH
    if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
        export PATH="${BIN_DIR}:${PATH}"
        SHELL_RC="$([ "${OS}" = "darwin" ] && echo "~/.zshrc" || echo "~/.bashrc")"
        echo "[!] Notice: Added ${BIN_DIR} to current PATH. Consider adding 'export PATH=\"${BIN_DIR}:\$PATH\"' to your ${SHELL_RC}"
    fi
    echo "[+] kind installed successfully: $(kind version)"
else
    echo "[+] kind is already installed: $(kind version)"
fi

echo "=== [durag / day-0] All prerequisites satisfied! ==="
