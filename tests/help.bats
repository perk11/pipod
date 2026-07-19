#!/usr/bin/env bats
# Tests for the user-facing help output (rendered by the actual pipod script,
# not the in-shell function — catches typos and confirms the new commands and
# options show up in `--help`).

load test_helper

@test "pipod --help exits 0" {
    run "$PIPOD" --help
    [ "$status" -eq 0 ]
}

@test "help lists the new stop command" {
    run "$PIPOD" --help
    [[ "$output" == *"  stop"* ]]
    [[ "$output" == *"Stop the current workspace/agent container"* ]]
}

@test "help lists the new --no-tty option" {
    run "$PIPOD" --help
    [[ "$output" == *"--no-tty"* ]]
    [[ "$output" == *"no pseudo-tty"* ]]
}

@test "help documents the -- pass-through" {
    run "$PIPOD" --help
    [[ "$output" == *"[-- ARGS...]"* ]]
    [[ "$output" == *"Anything after \`--\` is forwarded"* ]]
    [[ "$output" == *"pipod -- --print \"summary\""* ]]
}

@test "help usage line mentions the new [-- ARGS...] form" {
    run "$PIPOD" --help
    [[ "$output" == *"Usage: pipod [claude|codex] [OPTIONS] [COMMAND] [-- ARGS...]"* ]]
}

@test "-h is an alias for --help" {
    run "$PIPOD" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: pipod"* ]]
}
