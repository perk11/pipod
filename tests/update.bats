#!/usr/bin/env bats
# Integration tests for `pipod update` against a mocked `docker` binary. The
# mock (tests/docker-mock) logs every call; these verify the agent's own
# self-update command reaches `docker exec`, the container is (re)started only
# when needed, the no-network case warns, and the flow short-circuits before
# any build/run/recreate work.

load test_helper

# Per-test scratch dir: PATH shim, docker call log, isolated $HOME (so pipod's
# prepare_config never touches the real ~/.pipod).
setup() {
    BATS_TMPDIR_ABS="${BATS_TMPDIR:-/tmp}"
    WORK="$(mktemp -d "$BATS_TMPDIR_ABS/pipod-update.XXXXXX")"
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

# Run pipod with the mock docker first on PATH. Args are forwarded to pipod.
run_pipod() {
    DOCKER_MOCK_LOG="$DOCKER_LOG" PATH="$MOCK_BIN:$PATH" run "$PIPOD" "$@"
}

# Count occurrences of a docker subcommand in the call log. Each line in
# $DOCKER_LOG is NUL-separated fields; the first field is the subcommand.
docker_calls() {
    local needle="$1"
    [ -f "$DOCKER_LOG" ] || { echo 0; return; }
    awk -v needle="$needle" 'BEGIN{RS="\n"; FS="\0"} $1==needle{c++} END{print c+0}' "$DOCKER_LOG"
}

# The full command pipod passed to `docker exec` — fields 3 onward joined with
# single spaces (field 1 is `exec`, field 2 is the container name). Compared as
# a literal string so the exact argv (incl. the `sudo -H` prefix) is verified.
exec_cmd() {
    awk -F'\0' '$1=="exec"{for(i=3;i<=NF;i++)printf "%s%s",$i,(i<NF?" ":"");print""}' "$DOCKER_LOG"
}

@test "update with no container: exits 1 with a clear message" {
    DOCKER_MOCK_STATE=missing
    export DOCKER_MOCK_STATE
    run_pipod update
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
    [ "$(docker_calls exec)" = 0 ]
    [ "$(docker_calls start)" = 0 ]
    [ "$(docker_calls unpause)" = 0 ]
}

@test "update a running pi container: runs 'sudo -H pi update --self', no start" {
    DOCKER_MOCK_STATE=running
    export DOCKER_MOCK_STATE
    run_pipod update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updating pi"* ]]
    # docker exec <name> sudo -H pi update --self  (run as root: /usr/local is root-owned)
    [ "$(exec_cmd)" = "sudo -H pi update --self" ]
    [ "$(docker_calls exec)" = 1 ]
    # running container needs no start/unpause
    [ "$(docker_calls start)" = 0 ]
    [ "$(docker_calls unpause)" = 0 ]
}

@test "update claude: runs 'sudo -H claude update' against the claude container" {
    DOCKER_MOCK_STATE=running
    export DOCKER_MOCK_STATE
    run_pipod claude update
    [ "$status" -eq 0 ]
    awk -F'\0' '$1=="exec"{print $2}' "$DOCKER_LOG" | grep -qE '^pipod-claude-'
    [ "$(exec_cmd)" = "sudo -H claude update" ]
    [ "$(docker_calls exec)" = 1 ]
}

@test "update codex: runs 'sudo -H codex update' against the codex container" {
    DOCKER_MOCK_STATE=running
    export DOCKER_MOCK_STATE
    run_pipod codex update
    [ "$status" -eq 0 ]
    awk -F'\0' '$1=="exec"{print $2}' "$DOCKER_LOG" | grep -qE '^pipod-codex-'
    [ "$(exec_cmd)" = "sudo -H codex update" ]
    [ "$(docker_calls exec)" = 1 ]
}

@test "update junie: runs 'junie update' (no sudo) against the junie container" {
    DOCKER_MOCK_STATE=running
    export DOCKER_MOCK_STATE
    run_pipod junie update
    [ "$status" -eq 0 ]
    awk -F'\0' '$1=="exec"{print $2}' "$DOCKER_LOG" | grep -qE '^pipod-junie-'
    # junie updates its user-owned platform binary under ~/.local — no root needed
    [ "$(exec_cmd)" = "junie update" ]
    [ "$(docker_calls exec)" = 1 ]
}

@test "update an exited container: starts it first, then updates" {
    DOCKER_MOCK_STATE=exited
    export DOCKER_MOCK_STATE
    run_pipod update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting container pipod-"* ]]
    [ "$(docker_calls start)" = 1 ]
    [ "$(docker_calls exec)" = 1 ]
}

@test "update a paused container: unpauses it first, then updates" {
    DOCKER_MOCK_STATE=paused
    export DOCKER_MOCK_STATE
    run_pipod update
    [ "$status" -eq 0 ]
    [[ "$output" == *"Unpausing container pipod-"* ]]
    [ "$(docker_calls unpause)" = 1 ]
    [ "$(docker_calls exec)" = 1 ]
}

@test "update with -nn targets the no-network container and warns" {
    DOCKER_MOCK_STATE=running
    export DOCKER_MOCK_STATE
    run_pipod -nn update
    [ "$status" -eq 0 ]
    awk -F'\0' '$1=="exec"{print $2}' "$DOCKER_LOG" | grep -qE '^pipod-.*-nonet$'
    [[ "$output" == *"no Internet access"* ]]
    [ "$(docker_calls exec)" = 1 ]
}

@test "update short-circuits before any build/run/create work" {
    DOCKER_MOCK_STATE=running
    export DOCKER_MOCK_STATE
    run_pipod update
    [ "$(docker_calls build)" = 0 ]
    [ "$(docker_calls run)" = 0 ]
    [ "$(docker_calls network)" = 0 ]
}
