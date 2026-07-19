#!/usr/bin/env bats
# Integration tests for `pipod stop` against a mocked `docker` binary. The
# mock lives at tests/docker-mock and is controlled by env vars
# (DOCKER_MOCK_LOG, DOCKER_MOCK_STATE). Each test runs the real `pipod`
# script as a subprocess with the mock first on PATH.

load test_helper

# Per-test scratch dir: PATH shim, docker call log, isolated $HOME (so pipod's
# prepare_config never touches the real ~/.pipod). bats runs setup() before
# every @test in this file.
setup() {
    BATS_TMPDIR_ABS="${BATS_TMPDIR:-/tmp}"
    WORK="$(mktemp -d "$BATS_TMPDIR_ABS/pipod-stop.XXXXXX")"
    MOCK_BIN="$WORK/bin"
    mkdir -p "$MOCK_BIN"
    cp "$BATS_TEST_DIRNAME/docker-mock" "$MOCK_BIN/docker"
    chmod +x "$MOCK_BIN/docker"
    DOCKER_LOG="$WORK/docker.log"
    : > "$DOCKER_LOG"
    # Isolated HOME so pipod never sees the host's ~/.pipod, ~/.pi, etc.
    HOME="$WORK/home"
    mkdir -p "$HOME"
    export HOME
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

# Run pipod with the mock docker first on PATH. Args are forwarded to pipod.
# Sets $status, $output, $lines (bats run) and exposes $DOCKER_LOG.
run_pipod() {
    # `command -v docker` resolves to the mock because PATH is overridden here.
    DOCKER_MOCK_LOG="$DOCKER_LOG" PATH="$MOCK_BIN:$PATH" run "$PIPOD" "$@"
}

# Count occurrences of a docker subcommand in the call log. Each line in
# $DOCKER_LOG starts with the subcommand.
# Count how many times docker was invoked with the given subcommand.
# `awk` reserves `sub` as a builtin name, so the in-awk variable is `needle`.
docker_calls() {
    local needle="$1"
    [ -f "$DOCKER_LOG" ] || { echo 0; return; }
    # The mock logs NUL-separated fields; the first field is the subcommand.
    awk -v needle="$needle" 'BEGIN{RS="\n"; FS="\0"} $1==needle{c++} END{print c+0}' "$DOCKER_LOG"
}

@test "stop with no container: exits 1 with a clear message" {
    DOCKER_MOCK_STATE=missing
    export DOCKER_MOCK_STATE
    run_pipod stop
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
    [ "$(docker_calls kill)" = 0 ]
    [ "$(docker_calls inspect)" -ge 1 ]
}

@test "stop a running container: kills it and exits 0" {
    DOCKER_MOCK_STATE=running
    export DOCKER_MOCK_STATE
    run_pipod stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stopping pipod-"* ]]
    [ "$(docker_calls kill)" = 1 ]
}

@test "stop an exited container: reports not running, no kill" {
    DOCKER_MOCK_STATE=exited
    export DOCKER_MOCK_STATE
    run_pipod stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"is not running"* ]]
    [ "$(docker_calls kill)" = 0 ]
}

@test "stop a paused container: still kills it" {
    DOCKER_MOCK_STATE=paused
    export DOCKER_MOCK_STATE
    run_pipod stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stopping pipod-"* ]]
    [ "$(docker_calls kill)" = 1 ]
}

@test "stop targets the claude container when invoked with 'claude stop'" {
    DOCKER_MOCK_STATE=running
    export DOCKER_MOCK_STATE
    run_pipod claude stop
    [ "$status" -eq 0 ]
    # `docker kill <name>` is the second line field; verify the name has the
    # `pipod-claude-` prefix.
    awk -F'\0' '$1=="kill"{print $2}' "$DOCKER_LOG" | grep -qE '^pipod-claude-'
}

@test "stop targets the codex container when invoked with 'codex stop'" {
    DOCKER_MOCK_STATE=running
    export DOCKER_MOCK_STATE
    run_pipod codex stop
    [ "$status" -eq 0 ]
    awk -F'\0' '$1=="kill"{print $2}' "$DOCKER_LOG" | grep -qE '^pipod-codex-'
}

@test "stop with -nn targets the no-network container (name ends in -nonet)" {
    DOCKER_MOCK_STATE=running
    export DOCKER_MOCK_STATE
    run_pipod -nn stop
    [ "$status" -eq 0 ]
    awk -F'\0' '$1=="kill"{print $2}' "$DOCKER_LOG" | grep -qE '^pipod-.*-nonet$'
}

@test "stop inspect is called against the right container name" {
    DOCKER_MOCK_STATE=running
    export DOCKER_MOCK_STATE
    run_pipod stop
    # `docker inspect -f '{{.State.Status}}' <name>` — the name is field 4.
    awk -F'\0' '$1=="inspect"{print $4}' "$DOCKER_LOG" | grep -qE '^pipod-'
}

@test "stop short-circuits before any build/run/create work" {
    DOCKER_MOCK_STATE=missing
    export DOCKER_MOCK_STATE
    run_pipod stop
    [ "$(docker_calls build)" = 0 ]
    [ "$(docker_calls run)" = 0 ]
    [ "$(docker_calls network)" = 0 ]
}
