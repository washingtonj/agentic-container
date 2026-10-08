#!/usr/bin/env bash
set -euo pipefail

library=/usr/local/lib/agentic-container
sshd_config=/etc/agentic-container/sshd_config

source "$library/configure.sh"

enabled() {
  local features="${FEATURES:-}"
  case ",$features," in
    *,ssh,*) ;;
    *) features="ssh,$features" ;;
  esac
  [[ ",$features," == *",$1,"* ]]
}

start_orca() {
  local port="${ORCA_PORT:-6768}"
  local pairing_address="${ORCA_PAIRING_ADDRESS:-}"
  local -a args=(serve --port "$port" --pairing-address "$pairing_address")
  local -a extra_args=()

  if [[ -z "$pairing_address" ]]; then
    echo "ERROR: ORCA_PAIRING_ADDRESS is not set." >&2
    echo "Set it to an address your Orca client can reach." >&2
    exit 1
  fi

  unset DISPLAY || true

  if [[ "${ORCA_JSON:-0}" == "1" ]]; then
    args+=(--json)
  fi
  if [[ "${ORCA_MOBILE_PAIRING:-0}" == "1" ]]; then
    args+=(--mobile-pairing)
  fi
  if [[ "${ORCA_NO_SANDBOX:-0}" == "1" ]]; then
    export ELECTRON_DISABLE_SANDBOX=1
    extra_args+=(--no-sandbox)
  fi

  echo "Starting Orca serve on port ${port}"
  echo "  pairing-address: ${pairing_address}"
  echo "  user: agent (1000)"

  cd /home/agent
  exec runuser --preserve-environment -u agent -- env \
    ASDF_DATA_DIR=/home/agent/.asdf \
    NPM_CONFIG_PREFIX=/home/agent/.npm-global \
    PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/home/agent/.asdf/shims:/home/agent/.asdf/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/home/agent \
    XDG_CONFIG_HOME=/home/agent/.config \
    XDG_DATA_HOME=/home/agent/.local/share \
    XDG_CACHE_HOME=/home/agent/.cache \
    LIBGL_ALWAYS_SOFTWARE=1 \
    /opt/Orca/orca-ide "${extra_args[@]}" "${args[@]}"
}

# Orca takes PID 1 when enabled, so a crash restarts the container; SSH is left
# detached behind it and holds the foreground when Orca is not enabled. With
# neither enabled, the container stays up for whatever the other features need.
if enabled orca; then
  if enabled ssh; then
    sshd -f "$sshd_config" -E /dev/stderr
  fi
  start_orca
fi

if enabled ssh; then
  exec sshd -D -f "$sshd_config" -E /dev/stderr
fi

exec sleep infinity
