#!/usr/bin/env bash
set -euo pipefail

HOME_DIR=/home/agent

configure_ssh() {
  local ssh_dir="$HOME_DIR/.ssh"
  local host_key="$ssh_dir/ssh_host_ed25519_key"
  local client_key="$ssh_dir/id_ed25519_client"
  local authorized_keys="$ssh_dir/authorized_keys"

  mkdir -p /run/sshd "$ssh_dir"

  if [[ ! -f "$host_key" ]]; then
    ssh-keygen -q -t ed25519 -N '' -C 'agentic-container host key' -f "$host_key"
    chmod 600 "$host_key"
    chmod 644 "$host_key.pub"
    echo "[ssh] Generated host key at $host_key."
  fi

  if [[ ! -f "$client_key" ]]; then
    ssh-keygen -q -t ed25519 -N '' -C 'agentic-container client key' -f "$client_key"
    chmod 600 "$client_key"
    chmod 644 "$client_key.pub"
    chown agent:agent "$client_key" "$client_key.pub"
    cat "$client_key.pub" > "$authorized_keys"
    chmod 600 "$authorized_keys"
    chown agent:agent "$authorized_keys"
    echo "[ssh] Generated client keypair at $client_key and authorized it."
  fi

  sshd -t -f /etc/agentic-container/sshd_config
}

# The volume hides whatever the image had under /home/agent, so these come back
# on every start, owned by the agent.
for dir in "$HOME_DIR/.asdf" "$HOME_DIR/workspace"; do
  mkdir -p "$dir"
  chown agent:agent "$dir"
done

shopt -s nullglob
env_files=(/etc/agentic-container/env.d/*.env)
shopt -u nullglob

for env_file in "${env_files[@]}"; do
  source "$env_file"
done

features=${FEATURES:-}
case ",$features," in
  *,ssh,*) ;;
  *) features="ssh,$features" ;;
esac
for feature in ${features//,/ }; do
  case "$feature" in
    ssh) configure_ssh ;;
  esac
done
