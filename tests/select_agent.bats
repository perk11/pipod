#!/usr/bin/env bats
# Unit tests for select_agent: per-agent image tag, container prefix, run
# command, and bootstrap file set.

load test_helper

# select_agent reads $AGENT and these globals; set them to dummy values so the
# function can be exercised without touching the host's ~/.pi, ~/.claude, ~/.codex.
setup_select_agent() {
    PROJECT_DIR=/tmp/pipod-project
    CONFIG_DIR=/tmp/pipod-config
    WS_DIR="$CONFIG_DIR/workspaces/ws1"
    HOME=/tmp/pipod-home
}

@test "pi agent: RUN_CMD, image, prefix, env, bootstrap" {
    setup_select_agent
    AGENT=pi
    select_agent
    [ "$AGENT_LABEL" = "pi" ]
    [ "$IMAGE_TAG" = "pipod-pi-coding-agent" ]
    [ "$CONTAINER_PREFIX" = "pipod" ]
    [ "$BUILD_DIR" = "$PROJECT_DIR/pi" ]
    [ "$CONFIG_MOUNT_DEST" = "/home/ubuntu/.pi" ]
    [ "$BOOTSTRAP_SRC_DIR" = "$HOME/.pi/agent" ]
    [ "${BOOTSTRAP_FILES[0]}" = models.json ]
    [ "${BOOTSTRAP_FILES[1]}" = auth.json ]
    [ "${RUN_CMD[0]}" = pi ]
    [ "${#RUN_CMD[@]}" = 1 ]
    # AGENT_ENV is a single -e flag for pi
    [[ "${AGENT_ENV[*]}" = *"PI_CODING_AGENT_DIR=/home/ubuntu/.pi/agent"* ]]
}

@test "claude agent: RUN_CMD, image, prefix, env, bootstrap" {
    setup_select_agent
    AGENT=claude
    select_agent
    [ "$AGENT_LABEL" = "Claude Code" ]
    [ "$IMAGE_TAG" = "pipod-claude" ]
    [ "$CONTAINER_PREFIX" = "pipod-claude" ]
    [ "$BUILD_DIR" = "$PROJECT_DIR/claude" ]
    [ "$CONFIG_MOUNT_DEST" = "/home/ubuntu/.claude" ]
    [ "$BOOTSTRAP_SRC_DIR" = "$HOME/.claude" ]
    [ "${BOOTSTRAP_FILES[0]}" = .credentials.json ]
    [ "${BOOTSTRAP_FILES[1]}" = settings.json ]
    [ "${RUN_CMD[0]}" = claude ]
    [ "${#RUN_CMD[@]}" = 1 ]
    [[ "${AGENT_ENV[*]}" = *"CLAUDE_CONFIG_DIR=/home/ubuntu/.claude"* ]]
}

@test "codex agent: RUN_CMD includes --yolo, plus CODEX_SQLITE_HOME env" {
    setup_select_agent
    AGENT=codex
    select_agent
    [ "$AGENT_LABEL" = "Codex CLI" ]
    [ "$IMAGE_TAG" = "pipod-codex" ]
    [ "$CONTAINER_PREFIX" = "pipod-codex" ]
    [ "$BUILD_DIR" = "$PROJECT_DIR/codex" ]
    [ "$CONFIG_MOUNT_DEST" = "/home/ubuntu/.codex" ]
    [ "$BOOTSTRAP_SRC_DIR" = "$HOME/.codex" ]
    [ "${BOOTSTRAP_FILES[0]}" = auth.json ]
    [ "${BOOTSTRAP_FILES[1]}" = config.toml ]
    [ "${RUN_CMD[0]}" = codex ]
    [ "${RUN_CMD[1]}" = --yolo ]
    [ "${#RUN_CMD[@]}" = 2 ]
    [[ "${AGENT_ENV[*]}" = *"CODEX_HOME=/home/ubuntu/.codex"* ]]
    [[ "${AGENT_ENV[*]}" = *"CODEX_SQLITE_HOME=/home/ubuntu/.codex/state"* ]]
}

@test "junie agent: RUN_CMD is plain junie, config mounted at ~/.junie, config.json + settings.json + allowlist.json + secure_credentials.json bootstrapped" {
    setup_select_agent
    AGENT=junie
    select_agent
    [ "$AGENT_LABEL" = "Junie CLI" ]
    [ "$IMAGE_TAG" = "pipod-junie" ]
    [ "$CONTAINER_PREFIX" = "pipod-junie" ]
    [ "$BUILD_DIR" = "$PROJECT_DIR/junie" ]
    [ "$CONFIG_MOUNT_DEST" = "/home/ubuntu/.junie" ]
    [ "$BOOTSTRAP_SRC_DIR" = "$HOME/.junie" ]
    [ "${BOOTSTRAP_FILES[0]}" = config.json ]
    [ "${BOOTSTRAP_FILES[1]}" = settings.json ]
    [ "${BOOTSTRAP_FILES[2]}" = allowlist.json ]
    [ "${BOOTSTRAP_FILES[3]}" = secure_credentials.json ]
    [ "${#BOOTSTRAP_FILES[@]}" = 4 ]
    [ "${BOOTSTRAP_DIRS[0]}" = models ]
    [ "${BOOTSTRAP_DIRS[1]}" = mcp ]
    [ "${BOOTSTRAP_DIRS[2]}" = skills ]
    [ "${BOOTSTRAP_DIRS[3]}" = commands ]
    [ "${BOOTSTRAP_DIRS[4]}" = agents ]
    [ "${#BOOTSTRAP_DIRS[@]}" = 5 ]
    [ "${RUN_CMD[0]}" = junie ]
    [ "${#RUN_CMD[@]}" = 1 ]
    # Junie has no config-dir env var, so AGENT_ENV is empty.
    [ "${#AGENT_ENV[@]}" = 0 ]
    # The override shares the config mount's destination (replaces shared config).
    [ "$OVERRIDE_DEST" = "$CONFIG_MOUNT_DEST" ]
    [ "$CONFIG_ROOT" = "/home/ubuntu/.junie" ]
}

@test "WS_AGENT_DIR is derived from WS_DIR and the agent key" {
    setup_select_agent
    AGENT=codex;  select_agent; [ "$WS_AGENT_DIR" = "$WS_DIR/codex" ]
    AGENT=claude; select_agent; [ "$WS_AGENT_DIR" = "$WS_DIR/claude" ]
    AGENT=junie;  select_agent; [ "$WS_AGENT_DIR" = "$WS_DIR/junie" ]
    AGENT=pi;     select_agent; [ "$WS_AGENT_DIR" = "$WS_DIR/pi" ]
}

@test "each agent has its sessions dir in DATA_MOUNTS" {
    setup_select_agent
    AGENT=pi;     select_agent; [[ "${DATA_MOUNTS[*]}" = *"/home/ubuntu/.pi/agent/sessions"* ]]
    AGENT=claude; select_agent; [[ "${DATA_MOUNTS[*]}" = *"/home/ubuntu/.claude/projects"* ]]
    AGENT=codex;  select_agent; [[ "${DATA_MOUNTS[*]}" = *"/home/ubuntu/.codex/sessions"* ]]
    AGENT=junie;  select_agent; [[ "${DATA_MOUNTS[*]}" = *"/home/ubuntu/.junie/cli-sessions/sessions"* ]]
}
