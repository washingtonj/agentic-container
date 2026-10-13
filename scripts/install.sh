#!/usr/bin/env bash
set -euo pipefail

# Orca has no "latest" .deb URL, so the newest release tag is read from the
# redirect of /releases/latest.
resolve_latest_orca() {
  local tag
  tag=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
    https://github.com/stablyai/orca/releases/latest)
  tag="${tag##*/}"
  if [[ "$tag" != v* ]]; then
    echo "Cannot resolve the latest Orca release from: $tag" >&2
    exit 1
  fi
  printf '%s\n' "${tag#v}"
}

install_ssh() {
  apt-get install -y --no-install-recommends openssh-client openssh-server

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

  # Debian generates host keys when the package lands; drop them so every
  # volume generates its own instead of sharing one baked into the image.
  rm -f /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ecdsa_key /etc/ssh/ssh_host_rsa_key
}

install_asdf() {
  apt-get install -y --no-install-recommends bzip2 gawk unzip xz-utils

  local version="${ASDF_VERSION:-0.20.0}" arch
  case "${TARGETARCH:-amd64}" in
    amd64) arch=amd64 ;;
    arm64) arch=arm64 ;;
    *) echo "Unsupported asdf architecture: ${TARGETARCH}" >&2; exit 1 ;;
  esac

  curl -fsSL -o /tmp/asdf.tar.gz \
    "https://github.com/asdf-vm/asdf/releases/download/v${version}/asdf-v${version}-linux-${arch}.tar.gz"
  tar -xzf /tmp/asdf.tar.gz -C /usr/local/bin asdf
  rm /tmp/asdf.tar.gz

  cat > /etc/agentic-container/env.d/asdf.env <<'EOF'
export ASDF_DATA_DIR=/home/agent/.asdf
export NPM_CONFIG_PREFIX=/home/agent/.npm-global
export PATH=/home/agent/.npm-global/bin:/home/agent/.local/bin:/home/agent/.asdf/shims:/home/agent/.asdf/bin:$PATH
EOF

  cat > /etc/profile.d/asdf.sh <<'EOF'
[ -f /etc/agentic-container/env.d/asdf.env ] && . /etc/agentic-container/env.d/asdf.env
EOF

  asdf version
}

install_orca() {
  # The Electron UI and the computer-use tooling behind it: the Chromium/GTK
  # libraries, Xvfb, clipboard and input tools, and AT-SPI over python3-gi.
  apt-get install -y --no-install-recommends \
    xvfb zlib1g xdg-utils \
    libatk-bridge2.0-0t64 libatk1.0-0t64 libgtk-3-0t64 libnotify4 libnss3 \
    libasound2t64 libatspi2.0-0t64 libcairo2 libcups2t64 libdrm2 libgbm1 \
    libpango-1.0-0 libsecret-1-0 libx11-xcb1 libxcb-dri3-0 libxcomposite1 libxdamage1 \
    libxfixes3 libxkbcommon0 libxrandr2 libxrender1 libxss1 libxtst6 \
    gir1.2-atspi-2.0 python3 python3-gi \
    xclip xdotool

  # The GL libraries Electron loads are kept; the LLVM and Mesa drivers apt
  # dragged in with them are dropped at the end of the build (see purge_mesa),
  # because that purge breaks the apt state for anything installed after it.

  local version="${ORCA_VERSION:-latest}" deb_arch deb_name url deb
  if [[ "$version" == latest ]]; then
    version=$(resolve_latest_orca)
  fi

  deb_arch=$(dpkg --print-architecture)
  case "$deb_arch" in
    amd64 | arm64) ;;
    *) echo "Unsupported Orca architecture: $deb_arch" >&2; exit 1 ;;
  esac

  deb_name="orca-ide_${version}_${deb_arch}.deb"
  url="https://github.com/stablyai/orca/releases/download/v${version}/${deb_name}"

  # Not `local`: the EXIT trap fires after this function returns, by which time a
  # local variable is out of scope and `set -u` turns the cleanup into a build
  # failure ("tmp_dir: unbound variable").
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' EXIT

  # ORCA_DEB_CACHE is pointed at a BuildKit cache mount by the Dockerfile, so a
  # release that was already downloaded is reused instead of fetched again.
  deb="${ORCA_DEB_CACHE:-$tmp_dir}/$deb_name"
  if [[ -f "$deb" ]]; then
    echo "Using cached Orca package: $deb"
  else
    echo "Downloading: $url"
    curl -fsSL -o "$deb.new" "$url"
    mv "$deb.new" "$deb"
  fi

  dpkg-deb -x "$deb" "$tmp_dir/extracted"
  mv "$tmp_dir/extracted/opt/Orca" /opt/Orca

  chmod -R a+rX /opt/Orca
  printf '%s\n' "$version" > /opt/Orca/VERSION

  find /opt/Orca/locales -name '*.pak' \
    ! -name 'en-US.pak' ! -name 'en-GB.pak' -delete 2>/dev/null || true
  rm -f /opt/Orca/LICENSES.chromium.html

  test -x /opt/Orca/orca-ide
  echo "Installed Orca $version at /opt/Orca"
}

install_adb() {
  # The adb client the agent drives the emulator with; the emulator itself runs
  # in its own container and is reached over TCP. The Debian package tracks the
  # platform-tools major version, so it matches an API 34 emulator.
  apt-get install -y --no-install-recommends adb

  adb version
}

install_chrome() {
  # Debian builds Chromium for both amd64 and arm64; the fonts keep screenshots
  # from rendering text as boxes.
  apt-get install -y --no-install-recommends chromium fonts-liberation

  # Prove it runs headless, not merely that the packages installed.
  local profile_dir
  profile_dir=$(mktemp -d)
  chromium --headless --no-sandbox --disable-gpu --user-data-dir="$profile_dir" \
    --dump-dom about:blank >/dev/null
  rm -rf "$profile_dir"

  chromium --version
}

if [[ "${1:-}" == --print-latest-orca ]]; then
  resolve_latest_orca
  exit 0
fi

features=${FEATURES:-}
case ",$features," in
  *,ssh,*) ;;
  *) features="ssh,$features" ;;
esac

# Fixed order, so a FEATURES list like "adb,orca" builds the same image as
# "orca,adb". `orca` purges the LLVM/Mesa stack that Electron does not load,
# and that purge breaks the apt state for anything installed after it, so it
# has to run last.
# Drop the LLVM and Mesa drivers the Electron libraries dragged in: they are
# the bulk of the image and nothing loads them. This runs after every other
# feature, because `dpkg --purge --force-depends` leaves libgbm1 and libglx-mesa0
# pointing at mesa-libgallium, and any later apt-get install then fails with
# unmet dependencies.
purge_mesa() {
  apt-mark manual libgbm1 libgl1-mesa-dri libglx-mesa0
  dpkg --purge --force-depends libllvm19 mesa-libgallium libz3-4 2>/dev/null || true
}

ordered_features=""
for feature in ssh asdf orca chrome adb; do
  case ",$features," in
    *,$feature,*) ordered_features="${ordered_features:+$ordered_features,}$feature" ;;
  esac
done

apt-get update
for feature in ${ordered_features//,/ }; do
  case "$feature" in
    ssh) install_ssh ;;
    asdf) install_asdf ;;
    orca) install_orca ;;
    chrome) install_chrome ;;
    adb) install_adb ;;
    *)
      echo "Unknown feature '$feature'. Available: ssh asdf orca chrome adb" >&2
      exit 1
      ;;
  esac
done

case ",$features," in
  *,orca,*) purge_mesa ;;
esac

rm -rf /var/lib/apt/lists/*
