#!/usr/bin/env bash
# Shared setup for the cluster scripts: loads config and locates kubespray.
# Not meant to be run directly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${REPO_ROOT}/cluster.env" ]]; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/cluster.env"
else
  echo "error: cluster.env not found." >&2
  echo "       cp cluster.env.example cluster.env, then edit it." >&2
  exit 1
fi

: "${KUBESPRAY_DIR:?set KUBESPRAY_DIR in cluster.env}"
: "${INVENTORY:?set INVENTORY in cluster.env}"
: "${SSH_USER:?set SSH_USER in cluster.env}"
: "${NODES:?set NODES in cluster.env}"

if [[ ! -d "${KUBESPRAY_DIR}" ]]; then
  echo "error: kubespray not found at ${KUBESPRAY_DIR}" >&2
  echo "       git clone https://github.com/kubernetes-sigs/kubespray.git ${KUBESPRAY_DIR}" >&2
  exit 1
fi

# Run ansible-playbook from the kubespray checkout, inside its venv if present.
run_playbook() {
  local playbook="$1"; shift
  cd "${KUBESPRAY_DIR}"
  if [[ -f .venv/bin/activate ]]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
  fi
  ansible-playbook -i "${INVENTORY}" --become --become-user=root "${playbook}" "$@"
}

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
