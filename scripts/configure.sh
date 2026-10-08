#!/usr/bin/env bash
set -euo pipefail

HOME_DIR=/home/agent

configure_opencode_mcp() {
  [[ "${FEATURES:-}" == *orca* ]] || return 0

  local config_dir="$HOME_DIR/.config/opencode"
  local config_file="$config_dir/opencode.json"
  mkdir -p "$config_dir"

  python3 - "$config_file" <<'PY'
import json
import os
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
try:
    config = json.loads(config_path.read_text()) if config_path.exists() else {}
except json.JSONDecodeError:
    print(f"Cannot merge MCP settings into non-JSON config: {config_path}", file=sys.stderr)
    sys.exit(0)

servers = config.setdefault("mcp", {})

if os.environ.get("OPENCODE_MCP_BROWSER") == "1":
    servers["agentic-container-browser"] = {
        "type": "remote",
        "url": "http://browser-mcp:8931/mcp",
        "enabled": True,
    }
else:
    servers.pop("agentic-container-browser", None)
if os.environ.get("OPENCODE_MCP_ANDROID") == "1":
    servers["agentic-container-android"] = {
        "type": "remote",
        "url": "http://android-mcp:8000/mcp",
        "enabled": True,
    }
else:
    servers.pop("agentic-container-android", None)

config_path.write_text(json.dumps(config, indent=2) + "\n")
PY

  chown -R agent:agent "$config_dir"
}

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
    orca) configure_opencode_mcp ;;
  esac
done
