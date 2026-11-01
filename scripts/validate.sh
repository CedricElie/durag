#!/usr/bin/env bash
#
# validate.sh
# Tier-1 Local Pre-Flight Verification Script for durag.
# Runs fast, sub-second checks (Python tests, Helm linting, template generation)
# before committing or pushing code.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHARTS_DIR="${REPO_ROOT}/charts/durag"

WITH_DOCKER="false"
WITH_CLUSTER="false"
INSTALL_HOOK="false"

# Parse CLI options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --docker|--with-docker)
            WITH_DOCKER="true"
            shift 1
            ;;
        --cluster|--with-cluster)
            WITH_CLUSTER="true"
            shift 1
            ;;
        --all)
            WITH_DOCKER="true"
            WITH_CLUSTER="true"
            shift 1
            ;;
        --install-hook)
            INSTALL_HOOK="true"
            shift 1
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Tier-1 fast local validation runner (< 3 seconds)."
            echo ""
            echo "Options:"
            echo "  --docker          Also run Docker multi-stage build check"
            echo "  --cluster         Also verify Kind cluster connectivity and Helm release"
            echo "  --all             Run all checks (Python, Helm, Docker, and Cluster)"
            echo "  --install-hook    Install this script as a Git pre-commit hook"
            echo "  --help, -h        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# If user requested Git hook installation
if [ "${INSTALL_HOOK}" = "true" ]; then
    HOOK_FILE="${REPO_ROOT}/.git/hooks/pre-commit"
    if [ -d "${REPO_ROOT}/.git" ]; then
        mkdir -p "${REPO_ROOT}/.git/hooks"
        cat <<'EOF' > "${HOOK_FILE}"
#!/usr/bin/env bash
set -e
echo "=== [Git Hook] Running Tier-1 pre-commit validation ==="
./scripts/validate.sh
EOF
        chmod +x "${HOOK_FILE}"
        echo "[+] Git pre-commit hook installed to ${HOOK_FILE}"
        echo "    Validation will now run automatically before every 'git commit'."
        exit 0
    else
        echo "[-] Error: .git directory not found. Not a git repository."
        exit 1
    fi
fi

echo "=========================================================="
echo "    durag: Tier-1 Local Pre-Flight Validation             "
echo "=========================================================="
START_TIME=$(date +%s)

# 1. Python Unit Tests & Syntax Verification
echo -n "[*] Running Python unit tests... "
if command -v python3 >/dev/null 2>&1; then
    TEST_OUTPUT=$(PYTHONPATH="${REPO_ROOT}/src" python3 -m unittest discover "${REPO_ROOT}/tests" 2>&1)
    echo "PASSED"
else
    echo "SKIPPED (python3 not installed)"
fi

# 2. Helm Linting (Base chart)
echo -n "[*] Running Helm lint (base values)... "
if command -v helm >/dev/null 2>&1; then
    helm lint "${CHARTS_DIR}" >/dev/null 2>&1
    echo "PASSED"
else
    echo "SKIPPED (helm not installed)"
fi

# 3. Helm Linting (Local environment values)
echo -n "[*] Running Helm lint (local values)... "
if command -v helm >/dev/null 2>&1; then
    helm lint "${CHARTS_DIR}" -f "${CHARTS_DIR}/values-local.yaml" >/dev/null 2>&1
    echo "PASSED"
else
    echo "SKIPPED (helm not installed)"
fi

# 4. Helm Template Dry-Run Rendering
echo -n "[*] Testing Helm template rendering... "
if command -v helm >/dev/null 2>&1; then
    helm template durag "${CHARTS_DIR}" -f "${CHARTS_DIR}/values-local.yaml" >/dev/null 2>&1
    echo "PASSED"
else
    echo "SKIPPED (helm not installed)"
fi

# 5. Optional Docker Build Check
if [ "${WITH_DOCKER}" = "true" ]; then
    echo -n "[*] Testing Docker build (multi-stage)... "
    if command -v docker >/dev/null 2>&1; then
        docker build -q -t localhost:5001/durag:validate "${REPO_ROOT}" >/dev/null
        echo "PASSED"
    else
        echo "SKIPPED (docker not installed)"
    fi
fi

# 6. Optional Cluster Health Check
if [ "${WITH_CLUSTER}" = "true" ]; then
    echo -n "[*] Verifying Kind cluster and namespace... "
    if command -v kubectl >/dev/null 2>&1; then
        kubectl get namespace durag >/dev/null 2>&1
        kubectl get nodes >/dev/null 2>&1
        echo "PASSED"
    else
        echo "SKIPPED (kubectl not installed)"
    fi
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "=========================================================="
echo "    All Tier-1 checks passed successfully in ${DURATION}s!         "
echo "    Safe to commit and push.                              "
echo "=========================================================="
