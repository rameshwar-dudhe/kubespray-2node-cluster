#!/usr/bin/env bash
# Deploy the Kubernetes cluster with Kubespray.
set -euo pipefail
cd "$(dirname "$0")/.."
source .venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini \
    --become --become-user=root \
    cluster.yml "$@"
