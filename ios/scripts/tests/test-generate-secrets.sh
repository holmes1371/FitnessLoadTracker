#!/usr/bin/env bash
# Regression tests for ios/scripts/generate-secrets.sh.
# Run: bash ios/scripts/tests/test-generate-secrets.sh
# Exit code = number of failed cases.

set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/generate-secrets.sh"
PASS=0
FAIL=0

setup() {
    TESTDIR=$(mktemp -d)
    mkdir -p "$TESTDIR/parent/srcroot/FitnessLoadTracker"
    export SRCROOT="$TESTDIR/parent/srcroot"
    ENV_PATH="$TESTDIR/parent/.env"
    OUT_PATH="$SRCROOT/FitnessLoadTracker/Secrets.swift"
}

teardown() {
    rm -rf "$TESTDIR"
}

run_case() {
    local name="$1" expect="$2"
    shift 2
    setup
    "$@" > /tmp/test-output.txt 2>&1
    local actual=$?
    teardown

    if [ "$expect" = "success" ] && [ "$actual" -eq 0 ]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    elif [ "$expect" = "failure" ] && [ "$actual" -ne 0 ]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (expected $expect, got exit $actual)"
        cat /tmp/test-output.txt | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

case_happy_path() {
    cat > "$ENV_PATH" <<'EOF'
STRAVA_CLIENT_ID=test_id_12345
STRAVA_CLIENT_SECRET=test_secret_abcdef
EOF
    bash "$SCRIPT" || return 1
    grep -q 'static let stravaClientId = "test_id_12345"' "$OUT_PATH" || return 1
    grep -q 'static let stravaClientSecret = "test_secret_abcdef"' "$OUT_PATH" || return 1
}

case_missing_env() {
    bash "$SCRIPT"
}

case_empty_values() {
    cat > "$ENV_PATH" <<'EOF'
STRAVA_CLIENT_ID=
STRAVA_CLIENT_SECRET=
EOF
    bash "$SCRIPT"
}

case_only_one_value() {
    cat > "$ENV_PATH" <<'EOF'
STRAVA_CLIENT_ID=only_id
EOF
    bash "$SCRIPT"
}

case_quoted_values() {
    cat > "$ENV_PATH" <<'EOF'
STRAVA_CLIENT_ID="double_quoted"
STRAVA_CLIENT_SECRET='single_quoted'
EOF
    bash "$SCRIPT" || return 1
    grep -q 'static let stravaClientId = "double_quoted"' "$OUT_PATH" || return 1
    grep -q 'static let stravaClientSecret = "single_quoted"' "$OUT_PATH" || return 1
}

case_with_comments_and_blanks() {
    cat > "$ENV_PATH" <<'EOF'
# This is a comment
# Another comment

STRAVA_CLIENT_ID=id_with_comments
STRAVA_CLIENT_SECRET=secret_with_comments

# trailing comment
EOF
    bash "$SCRIPT" || return 1
    grep -q 'static let stravaClientId = "id_with_comments"' "$OUT_PATH" || return 1
}

run_case "happy path generates expected Swift"        success case_happy_path
run_case "missing .env errors"                        failure case_missing_env
run_case "both values empty errors"                   failure case_empty_values
run_case "only one of two values errors"              failure case_only_one_value
run_case "double + single quotes are stripped"        success case_quoted_values
run_case "comments and blank lines are tolerated"     success case_with_comments_and_blanks

echo
echo "$PASS passed, $FAIL failed"
exit "$FAIL"
