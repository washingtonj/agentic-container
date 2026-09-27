#!/usr/bin/env bash
set -euo pipefail

source /usr/local/lib/agentic-container/configure-runtime.sh
/usr/local/lib/agentic-container/configure-ssh.sh
exec /usr/local/lib/agentic-container/start-orca.sh
