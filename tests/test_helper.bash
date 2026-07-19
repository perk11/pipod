#!/usr/bin/env bash
# Common setup for bats tests. Sourced via `load test_helper` from each suite.
#
# Exposes:
#   $PIPOD       absolute path to the pipod script under test
#   source_pipod source the pipod script (defines functions, skips main flow)

PIPOD="${PIPOD:-$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/pipod}"
export PIPOD

# Source pipod so its functions are available in the test shell. pipod's
# source-guard (BASH_SOURCE != $0) skips strict mode and the main flow.
source_pipod() {
    # shellcheck source=/dev/null
    source "$PIPOD"
}

# bats runs this before every @test in any suite that does `load test_helper`,
# so each test starts with parse_args / select_agent / show_help available.
setup() {
    source_pipod
}

# Assert two strings are equal; on mismatch, print both with `od -c` so
# whitespace-only differences (trailing newlines, tabs) are visible.
assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        return 0
    fi
    {
        echo "FAIL: $desc"
        echo "  expected: $(printf '%q' "$expected")"
        echo "  actual:   $(printf '%q' "$actual")"
    } >&2
    return 1
}
