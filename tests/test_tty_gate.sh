#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DINIT="$ROOT/dinit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! command -v zsh >/dev/null 2>&1; then
  printf 'skip: zsh required for tty gate tests\n' >&2
  exit 0
fi

DINIT_ROOT="$TMP/dinit"
DINIT_LIB="$ROOT/lib"
export DINIT_ROOT DINIT_LIB

mkdir -p "$DINIT_ROOT"

LAST_OUT=""
LAST_RC=0

run_dinit_no_tty() {
  set +e
  LAST_OUT="$(env DINIT_ROOT="$DINIT_ROOT" DINIT_LIB="$DINIT_LIB" \
    zsh -f "$DINIT" "$@" </dev/null 2>&1)"
  LAST_RC=$?
  set -e
}

seed_pending_net() {
  python3 - "$DINIT_ROOT/state.json" <<'PY'
import json
import sys

path = sys.argv[1]
phases = {
    "preflight": "ok",
    "sudo": "pending",
    "net": "pending",
    "xcode": "ok",
    "brew": "ok",
    "bundle": "ok",
    "shell": "ok",
    "git_defaults": "ok",
    "ssh": "ok",
    "runtimes": "ok",
    "gh": "ok",
    "devmaster": "ok",
    "snapshot": "ok",
}
state = {
    "schema": "dinit.state.v1",
    "updated_at": "2026-01-01T00:00:00Z",
    "complete": False,
    "seeded": True,
    "phases": phases,
    "blocker": None,
}
with open(path, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
PY
}

seed_complete() {
  python3 - "$DINIT_ROOT/state.json" <<'PY'
import json
import sys

path = sys.argv[1]
phases = {
    "preflight": "ok",
    "sudo": "pending",
    "net": "ok",
    "xcode": "ok",
    "brew": "ok",
    "bundle": "ok",
    "shell": "ok",
    "git_defaults": "ok",
    "ssh": "ok",
    "runtimes": "ok",
    "gh": "ok",
    "devmaster": "ok",
    "snapshot": "ok",
}
state = {
    "schema": "dinit.state.v1",
    "updated_at": "2026-01-01T00:00:00Z",
    "complete": True,
    "seeded": True,
    "phases": phases,
    "blocker": None,
}
with open(path, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
PY
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

seed_pending_net
run_dinit_no_tty
assert_rc 1 "pending hydrate blocked without tty"
assert_output_contains "wants a real terminal" "pending hydrate explains tty requirement"

seed_complete
run_dinit_no_tty
assert_output_missing "wants a real terminal" "complete hydrate sitrep path has no tty gate"

run_dinit_no_tty sitrep
assert_output_missing "wants a real terminal" "sitrep works without tty"

printf 'all tty gate tests passed\n'
