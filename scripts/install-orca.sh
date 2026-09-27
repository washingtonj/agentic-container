#!/usr/bin/env bash
set -eu

orca_version="${ORCA_VERSION:-latest}"

resolve_latest_version() {
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

if [[ "${1:-}" == --print-latest ]]; then
  resolve_latest_version
  exit 0
fi

if [[ "$orca_version" == latest ]]; then
  orca_version=$(resolve_latest_version)
fi

deb_arch=$(dpkg --print-architecture)
case "$deb_arch" in
  amd64 | arm64) ;;
  *) echo "Unsupported Orca architecture: $deb_arch" >&2; exit 1 ;;
esac

deb_name="orca-ide_${orca_version}_${deb_arch}.deb"
url="https://github.com/stablyai/orca/releases/download/v${orca_version}/${deb_name}"

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
printf '%s\n' "$orca_version" > /opt/Orca/VERSION

find /opt/Orca/locales -name '*.pak' \
  ! -name 'en-US.pak' ! -name 'en-GB.pak' -delete 2>/dev/null || true
rm -f /opt/Orca/LICENSES.chromium.html

test -x /opt/Orca/orca-ide
echo "Installed Orca $orca_version at /opt/Orca"
