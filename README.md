# agentic-container

Container for leaving coding agents running unattended on a server, with CPU and memory capped in `docker-compose.yml`. IDEs and ADEs attach over its SSH server; Syncthing keeps agent skills and configuration in sync with the local machine; `asdf` installs the languages (`nodejs`, `rust`, ...). The agent runtime is currently [`orca serve`](https://github.com/stablyai/orca), following the official [Headless Linux Server](https://github.com/stablyai/orca/blob/main/docs/reference/headless-linux-server.md) guide; the image is built from this repository and the build resolves the newest Orca release, or the version you pin. The image is assembled from [build features](#features) — only `ssh` is on by default — so a container carries the runtime it needs and nothing else.

## Quick start

```bash
git clone https://github.com/washingtonj/agentic-container.git
cd agentic-container
cp .env.example .env           # FEATURES selects optional image features
docker compose up -d --build   # first build installs SSH and selected features
docker compose logs -f         # pairing URL
```

## Configuration

Set these in `.env` next to `docker-compose.yml` — compose reads it — or in your environment.

| Variable | Default | Purpose |
|---|---|---|
| `FEATURES` | `ssh` | Optional build features, comma-separated — `asdf`, `orca`, `chrome`; SSH is always included; changing it needs a rebuild |
| `HOST_BIND` | `127.0.0.1` | Host interface all published ports bind to — the runtime, SSH and Syncthing |
| `SSH_HOST_PORT` | `2222` | Host port mapped to the container SSH port |
| `ORCA_PORT` | `6768` | Container port for `orca serve`, published on `HOST_BIND` |
| `ORCA_PAIRING_ADDRESS` | value of `HOST_BIND` | Address the Orca client uses to reach this server — not a bind address; wildcards (`*`, `0.0.0.0`, `::`) are rejected, so set it explicitly when `HOST_BIND` is a wildcard |
| `ORCA_JSON` | `0` | Pass `--json` to `serve` |
| `ORCA_MOBILE_PAIRING` | `0` | Enable `--mobile-pairing` |
| `ORCA_NO_SANDBOX` | `0` | Enable only if Chromium reports sandbox errors |
| `OPENCODE_MCP_BROWSER` | `0` | Add the browser MCP endpoint to OpenCode config; start with Compose profile `mcp-browser` |
| `OPENCODE_MCP_ANDROID` | `0` | Add the Android MCP endpoint to OpenCode config; start with Compose profile `mcp-android` |
| `BROWSER_MEM_LIMIT` / `BROWSER_CPUS` | `2gb` / `1` | Browser MCP container resource caps |
| `ANDROID_EMULATOR_IMAGE` | `budtmo/docker-android:emulator_14.0` | Android emulator image tag |
| `ANDROID_EMULATOR_DEVICE` | `Nexus 5` | Device profile passed to Docker-Android |
| `ANDROID_EMULATOR_ARGS` | `-no-boot-anim -no-snapshot` | Additional emulator startup arguments |
| `ANDROID_MEM_LIMIT` / `ANDROID_CPUS` | `6gb` / `3` | Emulator resource caps |
| `MACVLAN_NETWORK` | `lan_macvlan` | Existing external Docker macvlan network used by the runtime override |
| `ANDROID_MCP_MEM_LIMIT` / `ANDROID_MCP_CPUS` | `512m` / `0.5` | Android MCP server resource caps |
| `SYNCTHING_USER` | (empty) | Syncthing GUI username; set together with the password to require auth |
| `SYNCTHING_PASSWORD` | (empty) | Syncthing GUI password, applied at container start |
| `VOLUME_NAME` | `agentic-container-home` | Engine name of the volume mounted at `/home/agent`; set it to an existing volume to keep that volume's data |
| `RUNTIME_MEM_LIMIT` | `8gb` | Memory cap for the runtime container; swap disabled |
| `RUNTIME_CPUS` | `2` | CPU limit for the runtime container; fractions allowed |
| `SYNCTHING_MEM_LIMIT` | `512m` | Memory cap for the Syncthing container; swap disabled |
| `SYNCTHING_CPUS` | `0.5` | CPU limit for the Syncthing container; fractions allowed |

## Features

The image is assembled at build time from features, so a container pays only for what it uses. `FEATURES` selects them; SSH is always installed, and `asdf`, `orca` and `chrome` are opt-in. `docker compose up -d --build` applies changes. A container built without `orca` runs no agent — it is the SSH server and whatever the other features put in it.

| Feature | Installs |
|---|---|
| `ssh` | Always installed: OpenSSH server and client, plus the sshd config and the runtime key generation behind them |
| `asdf` | `asdf` and the archive tools its plugins need: `bzip2`, `unzip`, `xz-utils`, `gawk` |
| `orca` | Orca, with the Chromium/GTK libraries, Xvfb, `xdotool`/`xclip` and AT-SPI that its Electron UI and computer use drive |
| `chrome` | Debian's Chromium with Liberation fonts — the headless browser MCP servers drive, see [Browser and Android MCP](#browser-and-android-mcp) |

The three scripts carry one step each of the lifecycle: [`scripts/install.sh`](scripts/install.sh) installs a feature at build time, [`scripts/configure.sh`](scripts/configure.sh) prepares the volume and its keys at every container start, and [`scripts/start.sh`](scripts/start.sh) — the entrypoint — runs what is enabled. Each holds one step per feature and skips the features `FEATURES` leaves out; an unknown name fails the build listing what exists. Adding a feature means adding its step to the scripts it needs.

## Runtime: Orca

[`scripts/install.sh`](scripts/install.sh) installs the upstream .deb at build time, for the `orca` feature; [`scripts/start.sh`](scripts/start.sh) starts it at container start as the unprivileged user `agent`. Orca's Electron UI and computer use account for everything else that feature installs — Chromium/GTK libraries, Xvfb, and `xdotool` with `python3-gi`; without it the image does not need them.

### Version

| Build arg | Default | Purpose |
|---|---|---|
| `ORCA_VERSION` | `latest` | Orca .deb version to install; `latest` resolves the newest release at build time |

The install layer is cached: the same `ORCA_VERSION` reuses the cached release instead of the newest, and when the layer does re-run, an already-downloaded package comes from the build cache, so only a new release is fetched. Pin a build with `ORCA_VERSION=1.4.215 docker compose build`.

### Upgrade

Orca only — its layer re-runs, everything before it is reused:

```bash
git pull
ORCA_VERSION=$(scripts/install.sh --print-latest-orca) docker compose up -d --build
```

Every layer, base image and Debian packages included:

```bash
docker compose build --pull --no-cache
docker compose up -d
```

The volume is preserved either way; the running release is `docker exec agentic-container cat /opt/Orca/VERSION`.

### Access from another network

To reach the container from both a LAN and an overlay (VPN / mesh), keep one pairing entry per network and mint one link for each: start the container with one address, scan, recreate with the other, scan. Both stay valid — paired-device keys live in the volume.

| Entry | `ORCA_PAIRING_ADDRESS` | Path |
|---|---|---|
| LAN | `orca.home` | Direct over the local network |
| Overlay | `orca.external.example` | Through the tunnel |

- **LAN name** — an `A` record (`orca.home → 192.168.0.10`) in the local DNS. If the overlay client intercepts DNS, add the `home` suffix to its **Local Domain Fallback** at that resolver so the name still resolves locally, keeping traffic on-link. The bare IP needs no DNS.
- **Overlay name** — a hostname only the overlay resolves to the server's overlay address (e.g. `100.64.0.10`), kept outside the LAN DNS suffix so the entries never collide.
- **Published ports** — a LAN entry needs them reachable on the LAN: `HOST_BIND=192.168.0.10`. That also exposes SSH and the Syncthing GUI — set `SYNCTHING_USER`/`SYNCTHING_PASSWORD` first.

## Optional LAN macvlan

To give only the runtime a LAN address while keeping container-to-container traffic on the private Compose bridge, first create a macvlan Docker network for your LAN. The override uses the existing network `lan_macvlan` by default; set `MACVLAN_NETWORK` in `.env` only if your network has a different name. Its parent interface, subnet, gateway, and address pool stay owned by that Docker network, avoiding a second overlapping macvlan configuration.

The runtime receives an IP from that network's address pool. Reserve the assigned IP in your LAN DHCP configuration if it needs to stay stable. Then start with the macvlan override:

```bash
docker compose -f docker-compose.yml -f docker-compose.macvlan.yml up -d --build
```

Only `runtime` joins the macvlan; it also stays on the default Compose bridge. With this override, the runtime's host-published port mappings are removed: reach its listening ports directly at its macvlan IP. Syncthing and the browser/Android MCP services remain on the bridge, with no auxiliary MCP ports published on the host or LAN. To disable macvlan, omit the override file. Docker macvlan normally prevents direct communication between the host and its macvlan containers.

## Browser and Android MCP

The MCP services are opt-in Compose profiles, separate from the runtime image. OpenCode MCP entries are merged into `/home/agent/.config/opencode/opencode.json` when `orca` is enabled and the corresponding `OPENCODE_MCP_*` option is `1`; existing OpenCode settings are preserved. Orca agents can reach the services by Compose DNS name.

Enable browser MCP:

```bash
OPENCODE_MCP_BROWSER=1 docker compose --profile mcp-browser up -d
```

This starts the official Playwright MCP container with headless Chromium. It exposes MCP internally at `http://browser-mcp:8931/mcp`; no host port is published.

Enable Android MCP:

```bash
OPENCODE_MCP_ANDROID=1 docker compose --profile mcp-android up -d
```

This starts the Android 14 emulator and Docker-Android's MCP service. The MCP service connects to the emulator over ADB and is available internally at `http://android-mcp:8000/mcp`. Android automation in this upstream MCP image currently includes device listing, app launch, opening URLs, foreground-window inspection, hardware buttons, and waits. Its MCP endpoint has no authentication, so keep it on the private Compose network. ADB is exposed only between Compose services.

For both, set both options and start both profiles. The runtime must include the `orca` feature for automatic OpenCode configuration. To use another MCP client, configure its remote MCP entry with the same endpoint URL; client config formats vary, and `mcp.json` is not a universal format. Starting a profile without setting its matching OpenCode option starts the service but does not add it to OpenCode config.

Docker-Android requires Linux and `/dev/kvm`; this setup passes the host device through. Emulator state is ephemeral by default. Resource limits can be adjusted with the variables in the configuration table.

## Network security

Ports `6768` (`orca serve`) and `22` (sshd) are administrative — **do not expose them on the public internet**; use a trusted LAN or a VPN / mesh. Upstream: *"Do not publish this port on the public internet; prefer Tailscale / WireGuard / trusted LAN."* The runtime runs as unprivileged user `agent` (uid 1000); sshd runs as root for privilege separation.

## Persistence

Mount a volume at `/home/agent` — compose key `home`, engine name `VOLUME_NAME` (default `agentic-container-home`), so the data survives renaming the project or the checkout directory. It holds:

- `.asdf/` — installed toolchains
- `.config/orca/` — Orca state and paired-device keys
- `.config/syncthing/` — syncthing config, certs and database
- `.ssh/` — SSH host key, generated client key, `authorized_keys`
- `workspace/` — also at `/workspace`

Without a volume all of it is lost on container recreation.

## SSH

### Keys

Public-key authentication only; password auth, PAM and root login are disabled. First boot generates a client keypair in the volume:

```bash
docker cp agentic-container:/home/agent/.ssh/id_ed25519_client ~/.ssh/agentic-container_client_key
chmod 600 ~/.ssh/agentic-container_client_key

ssh -p 2222 -i ~/.ssh/agentic-container_client_key agent@<docker-host>
```

To add your own key:

```bash
docker exec -i agentic-container bash -c \
  'cat >> /home/agent/.ssh/authorized_keys && chmod 600 /home/agent/.ssh/authorized_keys && chown agent:agent /home/agent/.ssh/authorized_keys' \
  < ~/.ssh/your_key.pub
```

The generated key stays authorized, so both keep working.

### Port forwarding

Dev servers started by the agents bind to loopback inside the container. Forward a port to open it locally:

```bash
ssh -N -p 2222 -i ~/.ssh/agentic-container_client_key \
  -L 3000:localhost:3000 -L 5173:localhost:5173 \
  agent@<host>
```

Forward to `localhost`, not `127.0.0.1`: inside the container `localhost` resolves to the `::1` address dev servers (Vite, etc.) bind to, while `127.0.0.1` is IPv4-only and refused.

## Toolchains & tools

### asdf

Installed by the `asdf` feature, no plugins:

```bash
docker exec -u agent -it agentic-container bash -lc \
  'asdf plugin add nodejs && asdf install nodejs latest && asdf set -u nodejs latest'
```

Any [asdf plugin](https://github.com/asdf-vm/asdf-plugins) works (`go`, `deno`, `python`, `rust`, ...). Installations persist in the volume.

### syncthing

Syncs folders of your choice — agent skills, config under `/home/agent/.config`, the workspace — with the local machine. Starts with the stack; `docker compose up -d runtime` brings up the runtime alone, `docker compose up -d syncthing` syncthing alone. Publishes `22000/tcp+udp`, `21027/udp` and the GUI on `8384`, all on `HOST_BIND`.

> **Authentication is required once exposed.** Syncthing ships with an unauthenticated GUI; anyone on the network could reconfigure it. Set credentials in `.env` (applied at every container start) or keep `HOST_BIND=127.0.0.1` and tunnel the GUI (see [port forwarding](#port-forwarding)):

```bash
# .env
SYNCTHING_USER=admin
SYNCTHING_PASSWORD=change-me
```

Add folders in the GUI under `/home/agent` so they persist in the volume, then pair devices. Syncthing is not pre-configured.
