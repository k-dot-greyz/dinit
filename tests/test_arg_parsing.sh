#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DINIT="$ROOT/dinit.sh"

if ! command -v zsh >/dev/null 2>&1; then
  printf 'skip: zsh required for arg parsing tests\n' >&2
  exit 0
fi

LAST_OUT=""
LAST_RC=0

run_dinit() {
  set +e
  LAST_OUT="$(zsh "$DINIT" "$@" 2>&1)"
  LAST_RC=$?
  set -e
}

assert_rc() {
  local want="$1" label="$2"
  if [[ "$LAST_RC" -ne "$want" ]]; then
    printf 'FAIL %s: expected exit %s got %s\n' "$label" "$want" "$LAST_RC" >&2
    printf '%s\n' "$LAST_OUT" >&2
    exit 1
  fi
  printf 'ok %s (exit %s)\n' "$label" "$want"
}

assert_output_contains() {
  local needle="$1" label="$2"
  if [[ "$LAST_OUT" != *"$needle"* ]]; then
    printf 'FAIL %s: output missing %q\n' "$label" "$needle" >&2
    printf '%s\n' "$LAST_OUT" >&2
    exit 1
  fi
  printf 'ok %s\n' "$label"
}

assert_output_missing() {
  local needle="$1" label="$2"
  if [[ "$LAST_OUT" == *"$needle"* ]]; then
    printf 'FAIL %s: output unexpectedly contains %q\n' "$label" "$needle" >&2
    printf '%s\n' "$LAST_OUT" >&2
    exit 1
  fi
  printf 'ok %s\n' "$label"
}

run_dinit sitrpe
assert_rc 2 "unknown subcommand exits 2"
assert_output_contains "unknown: sitrpe" "unknown subcommand message"

run_dinit --help
assert_rc 0 "--help exits 0"
assert_output_contains "dinit auth" "help lists auth"
assert_output_contains "purge-python" "help lists purge-python"

run_dinit env
assert_rc 0 "env subcommand exits 0"
assert_output_contains 'export PATH=' "env prints PATH export"

for subcmd in auth purge-python sitrep clone; do
  run_dinit "$subcmd"
  assert_output_missing "unknown:" "$subcmd is a recognized subcommand"
done

printf 'all arg parsing tests passed\n'
