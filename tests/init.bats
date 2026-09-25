#!/usr/bin/env bats
# Tests for the container's PID-1/init setup. New containers are created with
# `--init`, so Docker's bundled docker-init runs as PID 1 and reaps processes
# orphaned by finished exec sessions (a bare `sleep infinity` PID 1 never
# waits, so they would accumulate as zombies — and keep the idle-only
# auto-stop from firing). The idle threshold adapts: 2 (init + sleep) for
# --init containers, 1 (sleep only) for legacy containers created before
# --init, which are reused as-is until `./pipod -r` recreates them.

load test_helper

setup() {
    WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/pipod-init.XXXXXX")"
    MOCK_BIN="$WORK/bin"
    mkdir -p "$MOCK_BIN"
    cp "$BATS_TEST_DIRNAME/docker-mock" "$MOCK_BIN/docker"
    chmod +x "$MOCK_BIN/docker"
    DOCKER_LOG="$WORK/docker.log"
    : > "$DOCKER_LOG"
    HOME="$WORK/home"
    mkdir -p "$HOME"
    export HOME
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

# Run pipod in existing-container mode through STATE=exited, which enters via
# `docker start` and so skips the reuse branch's wait loop — with a static
# mock an already-idle process count would otherwise "wait for the stop to
# finish" for the full 15s.
run_pipod() {
    DOCKER_MOCK_LOG="$DOCKER_LOG" \
    DOCKER_MOCK_STATE=exited \
    DOCKER_MOCK_PS_ID=fakeID12345 \
    PATH="$MOCK_BIN:$PATH" \
        run "$PIPOD" "$@"
}

@test "new containers are created with --init (docker-init as PID 1 reaps zombies)" {
    # No PS_ID and STATE=missing -> no existing container: build + docker run.
    DOCKER_MOCK_LOG="$DOCKER_LOG" DOCKER_MOCK_STATE=missing \
    PATH="$MOCK_BIN:$PATH" run "$PIPOD"
    [ "$status" -eq 0 ]
    # The `docker run` call must carry --init as its own argument.
    [ "$(awk -F'\0' '$1=="run"{for(i=2;i<=NF;i++)if($i=="--init")f=1}END{print f+0}' "$DOCKER_LOG")" = 1 ]
}

@test "auto-stop fires when only init + sleep remain (--init container)" {
    DOCKER_MOCK_TOP_N=2 run_pipod
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stopping pipod-"* ]]
}

@test "no auto-stop while a session process is still alive" {
    DOCKER_MOCK_TOP_N=3 run_pipod
    [ "$status" -eq 0 ]
    [[ "$output" != *"Stopping pipod-"* ]]
}

@test "legacy container without --init keeps the old idle threshold of 1" {
    # init + sleep (TOP_N=2) is above the legacy threshold, so the container
    # stays up; only a single remaining process would auto-stop it.
    DOCKER_MOCK_INIT=false DOCKER_MOCK_TOP_N=2 run_pipod
    [ "$status" -eq 0 ]
    [[ "$output" != *"Stopping pipod-"* ]]

    DOCKER_MOCK_INIT=false DOCKER_MOCK_TOP_N=1 run_pipod
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stopping pipod-"* ]]
}
