#!/usr/bin/env bash
set -euo pipefail

SSH_DIR=/home/agent/.ssh
HOST_KEY=$SSH_DIR/ssh_host_ed25519_key
CLIENT_KEY=$SSH_DIR/id_ed25519_client
AUTHORIZED_KEYS=$SSH_DIR/authorized_keys
SSHD_CONFIG=/etc/agentic-container/sshd_config

mkdir -p /run/sshd "$SSH_DIR"

if [[ ! -f "$HOST_KEY" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C 'agentic-container host key' -f "$HOST_KEY"
  chmod 600 "$HOST_KEY"
  chmod 644 "$HOST_KEY.pub"
  echo "[ssh] Generated host key at $HOST_KEY."
fi

if [[ ! -f "$CLIENT_KEY" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C 'agentic-container client key' -f "$CLIENT_KEY"
  chmod 600 "$CLIENT_KEY"
  chmod 644 "$CLIENT_KEY.pub"
  chown agent:agent "$CLIENT_KEY" "$CLIENT_KEY.pub"
  cat "$CLIENT_KEY.pub" > "$AUTHORIZED_KEYS"
  chmod 600 "$AUTHORIZED_KEYS"
  chown agent:agent "$AUTHORIZED_KEYS"
  echo "[ssh] Generated client keypair at $CLIENT_KEY and authorized it."
fi

sshd -t -f "$SSHD_CONFIG"
exec /usr/sbin/sshd -f "$SSHD_CONFIG" -E /dev/stderr
