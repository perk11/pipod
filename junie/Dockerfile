FROM ubuntu:26.04

ARG HOST_UID=""
ARG HOST_GID=""

# Force a UTF-8 locale. The base image defaults to the C/POSIX locale, which is
# ASCII-only, so the Junie CLI (a Node TUI) can't encode non-ASCII output and
# renders Cyrillic, emoji, box-drawing, etc. as '?'. C.UTF-8 is built into
# modern glibc (Ubuntu 26.04), so no `locales` package / locale-gen is needed.
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# git: Junie's /review, --merge/--rebase, and built-in commit workflows rely on
# a git status snapshot of the workspace and .git markers.
# curl + unzip: the @jetbrains/junie npm package is a wrapper whose postinstall
# downloads the platform binary, and the installed shim (under ~/.local/bin)
# fetches/extracts channel updates at runtime, so both are required.
RUN apt-get update && \
    apt-get install -y --no-install-recommends nodejs npm git curl unzip sudo && \
    rm -rf /var/lib/apt/lists/*

# Install Junie CLI. The npm package's postinstall downloads the platform binary
# into ~/.local/share/junie and installs a bash shim at ~/.local/bin/junie,
# resolving both via os.homedir(). The build runs as root (HOME=/root), so force
# HOME to the runtime user's home so these land under /home/ubuntu and are found
# at runtime (the `junie` bin looks up ~/.local/bin/junie via os.homedir()).
RUN mkdir -p /home/ubuntu && \
    HOME=/home/ubuntu npm install -g @jetbrains/junie

# Pre-download the latest Junie release into the image. The npm package is
# version-pinned and lags behind the latest release (its postinstall fetches the
# pinned build); on first run Junie would otherwise auto-update and re-download
# the full ~200MB binary in *every* per-workspace container. `junie update` is
# Junie's own command — it fetches the latest release build, extracts it under
# ~/.local/share/junie/versions, flips the `current` symlink, and refreshes the
# shim. Auto-update stays enabled (only the initial version-gap download is
# baked in; newer releases still roll out at runtime). HOME is forced to
# /home/ubuntu so everything lands where the runtime ubuntu user expects, and
# the stale npm-pinned version is removed afterwards to keep the image lean.
# (The chown in the next RUN then fixes ownership of the freshly downloaded tree.)
RUN HOME=/home/ubuntu /home/ubuntu/.local/bin/junie update && \
    cur="$(basename "$(readlink -f /home/ubuntu/.local/share/junie/current 2>/dev/null || true)" 2>/dev/null || true)" && \
    if [ -n "$cur" ]; then \
      find /home/ubuntu/.local/share/junie/versions -mindepth 1 -maxdepth 1 -type d ! -name "$cur" -exec rm -rf {} +; \
    fi
# Map the ubuntu user (UID/GID 1000) to the host's UID/GID
RUN if [ -n "${HOST_GID}" ] && [ "${HOST_GID}" != "1000" ]; then \
      groupmod -g "${HOST_GID}" ubuntu; \
    fi && \
    if [ -n "${HOST_UID}" ] && [ "${HOST_UID}" != "1000" ]; then \
      usermod -u "${HOST_UID}" ubuntu; \
    fi && \
    chown -R ubuntu:ubuntu /home/ubuntu && \
    mkdir -p /home/ubuntu/.junie && \
    echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu && \
    chmod 440 /etc/sudoers.d/ubuntu

USER ubuntu
WORKDIR /workspace

ENTRYPOINT ["junie"]
CMD [""]
