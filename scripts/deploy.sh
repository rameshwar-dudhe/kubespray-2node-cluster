#!/usr/bin/env bash
# Build the cluster. Takes roughly 25 minutes on two nodes; most of that is
# downloading images and binaries.
#
# Usage: scripts/deploy.sh [extra ansible-playbook args]

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "deploying cluster from ${KUBESPRAY_DIR}"
run_playbook cluster.yml "$@"

cat <<'NOTE'

Deploy finished. A successful Ansible run does not by itself mean a healthy
cluster - always confirm with:

    kubectl get nodes
    kubectl get pods -A

See docs/coredns-loop-rca.md for a case where the run reported success while
DNS was completely broken.
NOTE
