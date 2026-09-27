# orca-devcontainer

Runs [`orca serve`](https://github.com/stablyai/orca) with `asdf` and an SSH server, following the official [Headless Linux Server](https://github.com/stablyai/orca/blob/main/docs/reference/headless-linux-server.md) guide. The image is built from this repository: the build resolves the newest Orca release, or the version you pin.

## Quick start

Clone and build — the first build takes a few minutes (apt packages plus the Orca package):

```bash
git clone https://github.com/washingtonj/orca-devcontainer.git
cd orca-devcontainer
cp .env.example .env
docker compose up -d --build
docker compose logs -f   # grab the pairing URL
```

## Environment variables

Set these in `.env` next to `docker-compose.yml` — compose reads it — or in your environment.

| Variable | Default | Purpose |
|---|---|---|
| `ORCA_PAIRING_ADDRESS` | value of `HOST_BIND` | Address the Orca client uses to reach this server — not a bind address; wildcards (`*`, `0.0.0.0`, `::`) are rejected, so set it explicitly when `HOST_BIND` is a wildcard |
| `ORCA_PORT` | `6768` | Internal port for `orca serve` |
| `ORCA_JSON` | `0` | Pass `--json` to `serve` |
| `ORCA_MOBILE_PAIRING` | `0` | Enable `--mobile-pairing` |
| `ORCA_NO_SANDBOX` | `0` | Enable only if Chromium reports sandbox errors |
| `HOST_BIND` | `127.0.0.1` | Host interface all published ports bind to — SSH and Syncthing (compose only) |
| `SSH_HOST_PORT` | `2222` | Host port mapped to the container SSH port (compose only) |
| `SYNCTHING_USER` | (empty) | Syncthing GUI username; set together with the password to require auth (compose only) |
| `SYNCTHING_PASSWORD` | (empty) | Syncthing GUI password, applied at container start (compose only) |

`ORCA_PORT` is pinned to `6768` by `docker-compose.yml`; change it there or in `.env`.

Build args (`docker compose` passes them through from your environment or `.env`):

| Build arg | Default | Purpose |
|---|---|---|
| `ORCA_VERSION` | `latest` | Orca .deb version to download; `latest` resolves the newest release during the build |

Docker caches the layer that installs Orca: a rebuild with the same value reuses the cached release instead of the newest one, and even when that layer re-runs, an already-downloaded package comes from the build cache, so only a new release is fetched. [Upgrade](#upgrade) shows the fast path (only that layer re-runs) and the full refresh; to pin a build:

```bash
ORCA_VERSION=1.4.215 docker compose build
```

`ORCA_PAIRING_ADDRESS` defaults to `HOST_BIND`, so the address clients use matches where the ports are published. Set it explicitly when the client reaches the server through a different address:

| Scenario | Value |
|---|---|
| LAN-only (see [Access from another network](#access-from-another-network)) | `orca.home` |
| Overlay — VPN or mesh (see [below](#access-from-another-network)) | `orca.external.example` |

## Access from another network

Keep two pairing entries on the client — one per network — and dial the one that matches where you are:

| Entry | `ORCA_PAIRING_ADDRESS` | Path |
|---|---|---|
| LAN | `orca.home` | Direct over the local network |
| Overlay (VPN / mesh) | `orca.external.example` | Through the tunnel to the server's remote address |

The **LAN entry** resolves only on the LAN: an `A` record `orca.home → 192.168.0.10` in the local DNS (router or local resolver). If the overlay client intercepts DNS, add the `home` suffix to its **Local Domain Fallback** pointing at that same resolver — fallback wins over remote DNS, so the name still resolves locally with the overlay on, keeping traffic on-link. A bare `192.168.0.10` needs no DNS at all.

The **overlay entry** is any hostname only the overlay resolves to the server's overlay address (e.g. `100.64.0.10`, set through the overlay's own DNS or an override rule); keep the name outside the LAN DNS suffix so the two entries never collide.

Mint one pairing link per entry: start the container with the LAN address, scan the URL on the laptop, then recreate with the overlay address and scan that one too. Both scans stay valid — paired-device keys persist in the volume — and the container can keep running with either address afterwards.

For the LAN entry to work, the published ports must be reachable on the LAN: set `HOST_BIND=192.168.0.10`. That also exposes SSH (`2222`) and the Syncthing GUI on the LAN — set `SYNCTHING_USER`/`SYNCTHING_PASSWORD` first (see [syncthing](#syncthing)).

## Network security

Ports `6768` (`orca serve`) and `22` (sshd) are administrative — **do not expose them on the public internet**. Upstream guidance:

> "Do not publish this port on the public internet; prefer Tailscale / WireGuard / trusted LAN."
> — [Headless Linux Server](https://github.com/stablyai/orca/blob/main/docs/reference/headless-linux-server.md)

Reach the server over a trusted LAN or a VPN / mesh (see [Access from another network](#access-from-another-network)).

Orca runs as unprivileged user `agent` (uid 1000); sshd runs as root for privilege separation.

## Persistence

Mount a volume at `/home/agent`. The volume holds:

- `.asdf/` — installed toolchains (asdf plugins and language versions)
- `.config/orca/` — Orca runtime state, paired-device keys
- `.config/syncthing/` — syncthing config, certs and database (device pairing, folder settings)
- `.ssh/` — SSH host key, generated client key, and `authorized_keys` for the `agent` user
- `workspace/` — accessible at `/workspace` via symlink

Without a volume, all of this is lost on container recreation.

## SSH

### Authentication & keys

Public-key authentication only; password auth, PAM, and root login are disabled.

On first boot the container generates a **client keypair** and stores it in the volume. Pull the private key out and use it to connect:

```bash
docker cp orca:/home/agent/.ssh/id_ed25519_client ~/.ssh/orca_client_key
chmod 600 ~/.ssh/orca_client_key

ssh -p 2222 -i ~/.ssh/orca_client_key agent@<docker-host>
```

To add your own key, append its public half to `/home/agent/.ssh/authorized_keys`:

```bash
docker exec -i orca bash -c \
  'cat >> /home/agent/.ssh/authorized_keys && chmod 600 /home/agent/.ssh/authorized_keys && chown agent:agent /home/agent/.ssh/authorized_keys' \
  < ~/.ssh/your_key.pub
```

The generated key remains authorized when you add your own, so you can keep both or remove it later.

### Port forwarding

Dev servers started by the runtime's agents bind to loopback inside the container, which is not reachable from the host. Forward a port over the SSH connection to open it on the laptop:

```bash
ssh -N -p 2222 -i ~/.ssh/orca_client_key \
  -L 3000:localhost:3000 -L 5173:localhost:5173 \
  agent@<host>
```

Use `localhost`, not `127.0.0.1`, as the forward target: inside the container `localhost` resolves to the `::1` address dev servers (Vite, etc.) bind to, while `127.0.0.1` is IPv4-only and refused. Then `http://localhost:3000` (or any forwarded port) works on the laptop.

## Toolchains & tools

### asdf

Installed **in the image** (no plugins). Install languages at any time:

```bash
docker exec -u agent -it orca bash -lc \
  'asdf plugin add nodejs && asdf install nodejs latest && asdf set -u nodejs latest'
```

Any [asdf plugin](https://github.com/asdf-vm/asdf-plugins) works (`go`, `deno`, `python`, `rust`, ...). Installations persist in the volume across container recreation.

### syncthing

Keeps a folder of your choice — e.g. the runtime's agent config under `/home/agent/.config`, or the workspace under `/home/agent/workspace` — in sync with your laptop. It starts with the stack; `docker compose up -d orca` brings up Orca alone:

```bash
docker compose up -d syncthing
```

It publishes its transfer and discovery ports (`22000/tcp+udp`, `21027/udp`) and the web UI (`8384`) on `HOST_BIND`. The web UI is served at `http://<docker-host>:8384`:

```bash
open http://<docker-host>:8384
```

> **Authentication is required once exposed.** Syncthing ships with an unauthenticated GUI; any user on the network could reconfigure it. Set the credentials in `.env` (applied at every container start) or restrict `HOST_BIND` to `127.0.0.1` and reach the GUI over an SSH tunnel (see [Port forwarding](#port-forwarding)):

```bash
# .env
SYNCTHING_USER=admin
SYNCTHING_PASSWORD=change-me
```

Then add a folder in the GUI and pair with your other devices — syncthing is not pre-configured, and choose folder paths under `/home/agent` so synced data persists in the `orca-home` volume. Device pairing and folder config persist there too.

## Upgrade

Orca only — the Orca layer re-runs, everything before it is reused:

```bash
git pull
ORCA_VERSION=$(scripts/install-orca.sh --print-latest) docker compose up -d --build
```

`--print-latest` resolves the newest release and passes it as the build arg; a release already in the build cache is not downloaded again. When you want a fresh base image and Debian packages too — every layer re-runs:

```bash
docker compose build --pull --no-cache
docker compose up -d
```

The volume is preserved either way, and Orca migrates its on-disk state forward. Check what the running container holds:

```bash
docker exec orca cat /opt/Orca/VERSION
```

## Troubleshooting

| Symptom | What to try |
|---|---|
| No pairing URL in logs | Verify `ORCA_PAIRING_ADDRESS` is reachable from the client (not `0.0.0.0`) |
| Client cannot connect | Check firewall / overlay routing / pairing address reachability |
| SSH forward logs `open failed: connect failed: Connection refused` | The target port has no listener, or the forward targets `127.0.0.1` while the dev server binds IPv6 — target `localhost` instead (see [Port forwarding](#port-forwarding)) |
| Chromium / sandbox errors | Set `ORCA_NO_SANDBOX=1`, recreate |
| Build fails downloading Orca | Check build network |
