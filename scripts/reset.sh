#!/usr/bin/env bash
# DESTRUCTIVE. Tears the cluster down and returns the nodes to bare machines.
#
# Usage: scripts/reset.sh [--yes] [extra ansible-playbook args]

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ASSUME_YES=0
if [[ "${1:-}" == "--yes" ]]; then ASSUME_YES=1; shift; fi

if [[ "${ASSUME_YES}" -eq 0 ]]; then
  echo "This destroys the cluster on: ${NODES}"
  read -r -p "Type 'yes' to continue: " reply
  [[ "${reply}" == "yes" ]] || { echo "aborted"; exit 1; }
fi

log "resetting cluster"
run_playbook reset.yml -e reset_confirmation=true "$@"
log "nodes are back to bare"
