#!/usr/bin/env bats
# Unit tests for the argument parser (parse_args). The parser is the surface
# most affected by `stop`, `--no-tty`, and `--` extra-args forwarding.

load test_helper

# Reset state and run the parser. After this returns, the parse_args globals
# (AGENT, RECREATE, NO_CACHE, SHELL_MODE, STOP_MODE, NO_NETWORK, NO_TTY,
# EXTRA_ARGS) are set in this shell.
parse() {
    parse_args "$@"
}

@test "no args: all defaults" {
    parse
    assert_eq "AGENT"        "pi"    "$AGENT"
    assert_eq "RECREATE"     "false" "$RECREATE"
    assert_eq "NO_CACHE"     ""      "$NO_CACHE"
    assert_eq "SHELL_MODE"   "false" "$SHELL_MODE"
    assert_eq "STOP_MODE"    "false" "$STOP_MODE"
    assert_eq "NO_NETWORK"   "false" "$NO_NETWORK"
    assert_eq "NO_TTY"       "false" "$NO_TTY"
    assert_eq "EXTRA_ARGS#"  "0"     "${#EXTRA_ARGS[@]}"
}

@test "claude selects the claude agent" {
    parse claude
    [ "$AGENT" = claude ]
}

@test "codex selects the codex agent" {
    parse codex
    [ "$AGENT" = codex ]
}

@test "junie selects the junie agent" {
    parse junie
    [ "$AGENT" = junie ]
}

@test "bash enables shell mode" {
    parse bash
    [ "$SHELL_MODE" = true ]
}

@test "stop enables stop mode" {
    parse stop
    [ "$STOP_MODE" = true ]
}

@test "-nn and --no-network both set NO_NETWORK" {
    parse -nn;       [ "$NO_NETWORK" = true ]
    parse --no-network; [ "$NO_NETWORK" = true ]
}

@test "-r and --recreate both set RECREATE" {
    parse -r;        [ "$RECREATE" = true ]
    parse --recreate; [ "$RECREATE" = true ]
}

@test "--no-cache is captured verbatim for docker build" {
    parse --no-cache
    [ "$NO_CACHE" = "--no-cache" ]
}

@test "--no-tty sets NO_TTY" {
    parse --no-tty
    [ "$NO_TTY" = true ]
}

@test "-h shows help and exits 0" {
    run parse_args -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: pipod"* ]]
    [[ "$output" == *"--help        Show this help message and exit"* ]]
}

@test "--help works the same as -h" {
    run parse_args --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: pipod"* ]]
}

@test "unknown option exits 1 with a stderr hint" {
    run parse_args --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option: --bogus"* ]]
    [[ "$output" == *"Usage: pipod"* ]]
}

@test "-- ends option parsing; remaining args go to EXTRA_ARGS" {
    parse -- --print summary
    [ "${EXTRA_ARGS[0]}" = "--print" ]
    [ "${EXTRA_ARGS[1]}" = summary      ]
    [ "${#EXTRA_ARGS[@]}" = 2           ]
}

@test "-- with no following args leaves EXTRA_ARGS empty" {
    parse --
    [ "${#EXTRA_ARGS[@]}" = 0 ]
}

@test "-- preserves args verbatim, including flags and spaces" {
    parse -- --print "hello world" --flag
    [ "${EXTRA_ARGS[0]}" = "--print"      ]
    [ "${EXTRA_ARGS[1]}" = "hello world"  ]
    [ "${EXTRA_ARGS[2]}" = "--flag"       ]
    [ "${#EXTRA_ARGS[@]}" = 3             ]
}

@test "options before -- are still parsed normally" {
    parse claude -nn --no-tty -- --permission-mode plan
    [ "$AGENT" = claude ]
    [ "$NO_NETWORK" = true ]
    [ "$NO_TTY" = true ]
    [ "${EXTRA_ARGS[0]}" = "--permission-mode" ]
    [ "${EXTRA_ARGS[1]}" = plan ]
}

@test "agent and -nn are encoded together with stop" {
    parse claude -nn stop
    [ "$AGENT" = claude ]
    [ "$NO_NETWORK" = true ]
    [ "$STOP_MODE" = true ]
}

@test "multiple flags combine freely" {
    parse --no-cache -r -nn --no-tty
    [ "$NO_CACHE" = "--no-cache" ]
    [ "$RECREATE" = true ]
    [ "$NO_NETWORK" = true ]
    [ "$NO_TTY" = true ]
}

@test "later agent command wins when both are given" {
    parse claude codex
    [ "$AGENT" = codex ]
    parse codex junie
    [ "$AGENT" = junie ]
}

@test "parse_args can be called repeatedly without state leaking" {
    parse claude -nn -- foo
    [ "$AGENT" = claude ]
    [ "${#EXTRA_ARGS[@]}" = 1 ]
    parse
    [ "$AGENT" = pi ]
    [ "$NO_NETWORK" = false ]
    [ "${#EXTRA_ARGS[@]}" = 0 ]
}
