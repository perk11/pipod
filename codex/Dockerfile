FROM ubuntu:26.04

ARG HOST_UID=""
ARG HOST_GID=""

# git is included because Codex detects the project root via .git markers and
# ships built-in commit workflows that rely on a git status snapshot. No fd /
# ripgrep: Codex is a Rust binary with built-in file/text search.
RUN apt-get update && \
    apt-get install -y --no-install-recommends nodejs npm git curl sudo && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g @openai/codex
# Map the ubuntu user (UID/GID 1000) to the host's UID/GID
RUN if [ -n "${HOST_GID}" ] && [ "${HOST_GID}" != "1000" ]; then \
      groupmod -g "${HOST_GID}" ubuntu; \
    fi && \
    if [ -n "${HOST_UID}" ] && [ "${HOST_UID}" != "1000" ]; then \
      usermod -u "${HOST_UID}" ubuntu; \
    fi && \
    chown -R ubuntu:ubuntu /home/ubuntu && \
    mkdir -p /home/ubuntu/.codex && \
    echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu && \
    chmod 440 /etc/sudoers.d/ubuntu

USER ubuntu
WORKDIR /workspace

ENTRYPOINT ["codex"]
CMD [""]
