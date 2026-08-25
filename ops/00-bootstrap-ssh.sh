#!/usr/bin/env bash
# Installs the control-node SSH key on both target nodes, then verifies
# key-based login + passwordless sudo.
# Usage: ./scripts/00-bootstrap-ssh.sh <ssh_user> <ssh_password>
set -euo pipefail

SSH_USER="${1:?usage: $0 <ssh_user> <ssh_password>}"
SSH_PASS="${2:?usage: $0 <ssh_user> <ssh_password>}"
NODES=(192.168.56.134 192.168.56.135)
KEY="$HOME/.ssh/id_ed25519"

[[ -f "$KEY" ]] || ssh-keygen -t ed25519 -N '' -f "$KEY"

for n in "${NODES[@]}"; do
  echo "==> $n : installing public key"
  sshpass -p "$SSH_PASS" ssh-copy-id -i "${KEY}.pub" \
      -o StrictHostKeyChecking=accept-new "${SSH_USER}@${n}"

  echo "==> $n : granting passwordless sudo to ${SSH_USER}"
  sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${n}" \
    "echo '$SSH_PASS' | sudo -S sh -c \"echo '${SSH_USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-kubespray && chmod 440 /etc/sudoers.d/90-kubespray\"" \
    >/dev/null 2>&1

  echo "==> $n : verifying"
  ssh -o BatchMode=yes "${SSH_USER}@${n}" \
      'echo "  login OK: $(hostname)"; sudo -n true && echo "  passwordless sudo OK"'
done
echo "All nodes bootstrapped."
