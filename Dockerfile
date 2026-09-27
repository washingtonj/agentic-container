# syntax=docker/dockerfile:1

FROM debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    ORCA_PORT=6768

ARG TARGETARCH
ARG ORCA_VERSION

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    bzip2 ca-certificates curl gawk git ripgrep unzip xdg-utils xz-utils \
    openssh-client openssh-server \
    xvfb zlib1g \
    libatk-bridge2.0-0t64 libatk1.0-0t64 libgtk-3-0t64 libnotify4 libnss3 \
    libasound2t64 libatspi2.0-0t64 libcairo2 libcups2t64 libdrm2 libgbm1 \
    libpango-1.0-0 libsecret-1-0 libx11-xcb1 libxcb-dri3-0 libxcomposite1 libxdamage1 \
    libxfixes3 libxkbcommon0 libxrandr2 libxrender1 libxss1 libxtst6 \
    gir1.2-atspi-2.0 python3 python3-gi \
    xclip xdotool \
 && apt-mark manual libgbm1 libgl1-mesa-dri libglx-mesa0 \
 && dpkg --purge --force-depends libllvm19 mesa-libgallium libz3-4 2>/dev/null || true \
 && rm -f /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ecdsa_key /etc/ssh/ssh_host_rsa_key \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --uid 1000 --create-home --user-group --shell /bin/bash -p '*' agent \
 && mkdir -p /home/agent/workspace /etc/devserver/env.d \
 && ln -s /home/agent/workspace /workspace

# Build-only scripts are bind-mounted into their RUN, so they never reach the image.
RUN --mount=type=bind,source=scripts/install-asdf.sh,target=/tmp/install-asdf.sh \
    TARGETARCH="${TARGETARCH:-amd64}" bash /tmp/install-asdf.sh

RUN --mount=type=bind,source=scripts/install-ssh.sh,target=/tmp/install-ssh.sh \
    bash /tmp/install-ssh.sh

# ORCA_VERSION is this step's only changing input, so a new release re-runs it and
# nothing before it; /var/cache/orca reuses .debs already downloaded.
RUN --mount=type=bind,source=scripts/install-orca.sh,target=/tmp/install-orca.sh \
    --mount=type=cache,target=/var/cache/orca,sharing=locked \
    ORCA_DEB_CACHE=/var/cache/orca ORCA_VERSION="$ORCA_VERSION" \
    bash /tmp/install-orca.sh

# Runtime-only scripts, and the files edited most often, kept last so an edit
# rebuilds nothing before them.
COPY --chmod=755 \
    scripts/configure-runtime.sh \
    scripts/configure-ssh.sh \
    scripts/entrypoint.sh \
    scripts/start-orca.sh \
    /usr/local/lib/devserver/

WORKDIR /home/agent

EXPOSE 22 6768

ENTRYPOINT ["/usr/local/lib/devserver/entrypoint.sh"]
