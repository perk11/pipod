FROM ubuntu:26.04

ARG HOST_UID=""
ARG HOST_GID=""

# git is included because Claude Code's default system prompt ships built-in
# commit/PR workflows and relies on a git status snapshot of the workspace.
RUN apt-get update && \
    apt-get install -y --no-install-recommends nodejs npm fd-find ripgrep git curl sudo && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code
# Map the ubuntu user (UID/GID 1000) to the host's UID/GID
RUN if [ -n "${HOST_GID}" ] && [ "${HOST_GID}" != "1000" ]; then \
      groupmod -g "${HOST_GID}" ubuntu; \
    fi && \
    if [ -n "${HOST_UID}" ] && [ "${HOST_UID}" != "1000" ]; then \
      usermod -u "${HOST_UID}" ubuntu; \
    fi && \
    chown -R ubuntu:ubuntu /home/ubuntu && \
    mkdir -p /home/ubuntu/.claude && \
    echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu && \
    chmod 440 /etc/sudoers.d/ubuntu

USER ubuntu
WORKDIR /workspace

ENTRYPOINT ["claude"]
CMD [""]
