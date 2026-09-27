#!/usr/bin/env bash
set -eu

mkdir -p /etc/agentic-container

cat > /etc/agentic-container/sshd_config <<'EOF'
Port 22
ListenAddress 0.0.0.0
ListenAddress ::
HostKey /home/agent/.ssh/ssh_host_ed25519_key
AuthorizedKeysFile /home/agent/.ssh/authorized_keys
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers agent
X11Forwarding no
PrintMotd no
UsePAM no
EOF
