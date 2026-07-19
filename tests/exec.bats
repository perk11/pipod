#!/usr/bin/env bats
# End-to-end tests for the `--` argument pass-through. These run the real
# pipod script with a mocked docker (existing-container path) and verify the
# exact argv that reaches `docker exec`, i.e. that the agent's RUN_CMD plus
# EXTRA_ARGS (plus the right -i/-it flag) are composed correctly.

load test_helper

setup() {
    WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/pipod-exec.XXXXXX")"
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

# Run pipod in existing-container mode: docker ps returns a fake ID (skipping
# the build/run branch), state is running (no start needed), TOP_N=2 keeps the
# auto-stop condition (`<=1`) false so the background `docker kill &` doesn't
# race the test's log read.
run_pipod() {
    DOCKER_MOCK_LOG="$DOCKER_LOG" \
    DOCKER_MOCK_STATE=running \
    DOCKER_MOCK_PS_ID=fakeID12345 \
    DOCKER_MOCK_TOP_N=2 \
    PATH="$MOCK_BIN:$PATH" \
        run "$PIPOD" "$@"
}

# Read field N (1-indexed) of the agent `docker exec` invocation directly
# from the log file. (Command substitution would drop the NUL separators.)
# Only matches execs that carry -it/-i: under `--no-network` pipod also runs
# probe `docker exec node -e …` calls (no -it/-i) which we want to exclude.
exec_field() {
    awk -F'\0' -v idx="$1" '$1=="exec" && ($2=="-it" || $2=="-i"){print $idx}' "$DOCKER_LOG"
}

# Total field count of the agent `docker exec` line (exec, -it/-i, <name>, …).
exec_argc() {
    awk -F'\0' '$1=="exec" && ($2=="-it" || $2=="-i"){print NF}' "$DOCKER_LOG"
}

@test "no extra args: docker exec invokes just the agent (pi)" {
    run_pipod
    [ "$status" -eq 0 ]
    [ "$(exec_field 2)" = "-it" ]
    [ "$(exec_field 4)" = "pi" ]
    # 4 fields total: exec, -it, <name>, pi
    [ "$(exec_argc)" = 4 ]
}

@test "-- forwards args to pi verbatim" {
    run_pipod -- --print "hello world"
    [ "$status" -eq 0 ]
    [ "$(exec_field 4)" = "pi" ]
    [ "$(exec_field 5)" = "--print" ]
    [ "$(exec_field 6)" = "hello world" ]
    [ "$(exec_argc)" = 6 ]
}

@test "--no-tty swaps -it for -i in the exec call" {
    run_pipod --no-tty -- --print summary
    [ "$status" -eq 0 ]
    [ "$(exec_field 2)" = "-i" ]
}

@test "-- forwards args after codex's RUN_CMD (codex --yolo)" {
    run_pipod codex -- arg1 arg2
    [ "$status" -eq 0 ]
    [ "$(exec_field 4)" = "codex" ]
    [ "$(exec_field 5)" = "--yolo" ]
    [ "$(exec_field 6)" = "arg1" ]
    [ "$(exec_field 7)" = "arg2" ]
}

@test "-- forwards args to claude" {
    run_pipod claude -- --permission-mode plan
    [ "$status" -eq 0 ]
    [ "$(exec_field 4)" = "claude" ]
    [ "$(exec_field 5)" = "--permission-mode" ]
    [ "$(exec_field 6)" = "plan" ]
}

@test "bash shell mode: extra args go to bash after the name" {
    run_pipod bash -- -c "echo hi"
    [ "$status" -eq 0 ]
    [ "$(exec_field 4)" = "bash" ]
    [ "$(exec_field 5)" = "-c" ]
    [ "$(exec_field 6)" = "echo hi" ]
}

@test "bash shell mode also respects --no-tty" {
    run_pipod --no-tty bash
    [ "$status" -eq 0 ]
    [ "$(exec_field 2)" = "-i" ]
    [ "$(exec_field 4)" = "bash" ]
}

@test "container name in exec is the workspace/agent slug" {
    run_pipod -- --print x
    [ "$status" -eq 0 ]
    [[ "$(exec_field 3)" == pipod-* ]]
}

@test "container name reflects agent + -nn" {
    run_pipod claude -nn -- foo
    [ "$status" -eq 0 ]
    [[ "$(exec_field 3)" == pipod-claude-*-nonet ]]
}
