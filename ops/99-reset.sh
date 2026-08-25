#!/usr/bin/env bash
# DESTRUCTIVE: tears the cluster back down to bare nodes.
set -euo pipefail
cd "$(dirname "$0")/.."
source .venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini \
    --become --become-user=root \
    reset.yml "$@"
