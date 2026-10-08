# syntax=docker/dockerfile:1

FROM debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    ORCA_PORT=6768

ARG TARGETARCH
ARG ORCA_VERSION

# Present in every build: TLS trust for the installers, git and ripgrep for the agent.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git ripgrep \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --uid 1000 --create-home --user-group --shell /bin/bash -p '*' agent \
 && mkdir -p /home/agent/workspace /etc/agentic-container/env.d /usr/local/lib/agentic-container \
 && ln -s /home/agent/workspace /workspace

# Comma-separated build features — ssh, asdf, orca, chrome — installed by
# scripts/install.sh. Only ssh is on by default: everything else costs image
# size, so it is paid for only where it is used. The runtime scripts read the
# same list to decide which steps to configure and start.
ARG FEATURES="ssh"
ENV FEATURES="${FEATURES}"

# Build-only scripts are bind-mounted into their RUN, so they never reach the
# image. The orca cache mount keeps already-fetched Orca .debs across rebuilds.
RUN --mount=type=bind,source=scripts,target=/tmp/scripts \
    --mount=type=cache,target=/var/cache/orca,sharing=locked \
    ORCA_DEB_CACHE=/var/cache/orca bash /tmp/scripts/install.sh

COPY --chmod=755 \
    scripts/configure.sh \
    scripts/start.sh \
    /usr/local/lib/agentic-container/

WORKDIR /home/agent

EXPOSE 22

ENTRYPOINT ["/usr/local/lib/agentic-container/start.sh"]
