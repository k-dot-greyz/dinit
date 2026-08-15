#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/retry.sh"

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" != "$want" ]]; then
    printf 'FAIL %s: got %q want %q\n' "$label" "$got" "$want" >&2
    exit 1
  fi
  printf 'ok %s\n' "$label"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
COUNTER="$TMP/n"
printf '0' >"$COUNTER"

export DINIT_RETRY_SLEEP=0

flaky() {
  local n
  n="$(cat "$COUNTER")"
  n=$((n + 1))
  printf '%s' "$n" >"$COUNTER"
  if [[ "$n" -lt 3 ]]; then
    return 1
  fi
  return 0
}

retry_transient 3 flaky
assert_eq "$(cat "$COUNTER")" "3" "retries until success within cap"

printf '0' >"$COUNTER"
always_fail() {
  local n
  n="$(cat "$COUNTER")"
  printf '%s' $((n + 1)) >"$COUNTER"
  return 1
}

set +e
retry_transient 3 always_fail
rc=$?
set -e
assert_eq "$rc" "1" "exhausted retries return failure"
assert_eq "$(cat "$COUNTER")" "3" "runs exactly attempts times on failure"

printf 'all retry_transient tests passed\n'
