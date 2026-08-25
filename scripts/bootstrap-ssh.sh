#!/usr/bin/env bash
# Install this machine's SSH public key on every node, then verify key-based
# login and passwordless sudo.
#
# Usage: scripts/bootstrap-ssh.sh <ssh_password>
#
# The password is only used to copy the key across. Everything afterwards,
# including the whole kubespray run, is key-based.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SSH_PASS="${1:-}"
if [[ -z "${SSH_PASS}" ]]; then
  echo "usage: $0 <ssh_password>" >&2
  exit 1
fi

command -v sshpass >/dev/null || { echo "error: sshpass is not installed" >&2; exit 1; }

[[ -f "${SSH_KEY}" ]] || { log "generating ${SSH_KEY}"; ssh-keygen -t ed25519 -N '' -f "${SSH_KEY}"; }

for node in ${NODES}; do
  log "${node}: installing public key"
  sshpass -p "${SSH_PASS}" ssh-copy-id -i "${SSH_KEY}.pub" \
      -o StrictHostKeyChecking=accept-new "${SSH_USER}@${node}"

  if [[ "${SSH_USER}" != "root" ]]; then
    log "${node}: granting passwordless sudo to ${SSH_USER}"
    sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=accept-new "${SSH_USER}@${node}" \
      "echo '${SSH_PASS}' | sudo -S sh -c \
       \"echo '${SSH_USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-kubespray && \
         chmod 440 /etc/sudoers.d/90-kubespray\"" >/dev/null 2>&1
  fi

  log "${node}: verifying"
  ssh -i "${SSH_KEY}" -o BatchMode=yes "${SSH_USER}@${node}" \
      'echo "    login OK: $(hostname)"; sudo -n true && echo "    sudo OK"'
done

log "all nodes ready"
