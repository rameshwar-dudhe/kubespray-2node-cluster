#!/usr/bin/env bash
# Copy admin.conf off the control plane to ~/.kube/config and rewrite the
# server address so kubectl works from this machine.
#
# Usage: scripts/fetch-kubeconfig.sh

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${CONTROL_PLANE:?set CONTROL_PLANE in cluster.env}"

KUBECONFIG_PATH="${HOME}/.kube/config"

if [[ -f "${KUBECONFIG_PATH}" ]]; then
  backup="${KUBECONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
  log "backing up existing kubeconfig to ${backup}"
  cp "${KUBECONFIG_PATH}" "${backup}"
fi

mkdir -p "${HOME}/.kube"
log "fetching admin.conf from ${CONTROL_PLANE}"
ssh -i "${SSH_KEY}" -o BatchMode=yes "${SSH_USER}@${CONTROL_PLANE}" \
    'cat /etc/kubernetes/admin.conf' > "${KUBECONFIG_PATH}"

sed -i "s#https://127\.0\.0\.1:6443#https://${CONTROL_PLANE}:6443#g; \
        s#https://localhost:6443#https://${CONTROL_PLANE}:6443#g" "${KUBECONFIG_PATH}"
chmod 600 "${KUBECONFIG_PATH}"

log "kubeconfig written to ${KUBECONFIG_PATH}"
kubectl get nodes 2>/dev/null || log "kubectl not on PATH - kubeconfig is still in place"
