#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

print() {
  if [[ "${1:-}" == "-r" ]]; then
    shift
    [[ "${1:-}" == "--" ]] && shift
    printf '%s' "$1"
    return 0
  fi
  printf '%s\n' "$*"
}

DINIT_ROOT="$TMP/dinit"
DINIT_LIB="$ROOT/lib"
ZSHRC="$TMP/.zshrc"
DEVMASTER_DIR="$TMP/dev-master"
PYTHON_PIN="3.14"
export DINIT_ROOT DINIT_LIB ZSHRC DEVMASTER_DIR PYTHON_PIN
mkdir -p "$DINIT_ROOT"

# shellcheck source=/dev/null
source "$ROOT/lib/state.sh"

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" != "$want" ]]; then
    printf 'FAIL %s: got %q want %q\n' "$label" "$got" "$want" >&2
    exit 1
  fi
  printf 'ok %s\n' "$label"
}

assert_fail() {
  local label="$1"
  shift
  set +e
  "$@" >/dev/null 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    printf 'FAIL %s: expected command to fail\n' "$label" >&2
    exit 1
  fi
  printf 'ok %s\n' "$label"
}

mark_required_ok() {
  local p
  for p in preflight net xcode brew bundle shell git_defaults ssh runtimes gh devmaster snapshot; do
    state_set_phase "$p" ok
  done
}

state_init

assert_eq "$(state_is_complete)" "false" "fresh state is not complete"
assert_eq "$(state_phase_kind sudo)" "session" "sudo is a session phase"
assert_eq "$(state_phase_kind gh)" "human" "gh is a human phase"
assert_eq "$(state_phase_kind brew)" "required" "brew is required"
assert_eq "$(state_phase_skippable gh)" "true" "gh is skippable"
assert_eq "$(state_phase_skippable brew)" "false" "brew is not skippable"

mark_required_ok
assert_eq "$(state_phase_status sudo)" "pending" "sudo stays pending after required ok"
assert_eq "$(state_is_complete)" "true" "complete ignores session sudo"
assert_eq "$(state_first_pending)" "" "no pending required work when only sudo is open"

state_set_phase gh pending
assert_eq "$(state_is_complete)" "false" "pending human phase blocks complete"
assert_eq "$(state_first_pending)" "gh" "first pending skips session sudo"

state_skip_phase gh "auth skipped (--skip-auth)" "dinit auth"
assert_eq "$(state_phase_status gh)" "skipped" "gh can be skipped"
assert_eq "$(state_is_complete)" "true" "skipped human phase does not block complete"
assert_eq "$(state_first_pending)" "" "skipped phases are not pending work"

assert_fail "cannot skip required brew" state_skip_phase brew "nope" "dinit"

state_reset_phase gh
assert_eq "$(state_phase_status gh)" "pending" "retry resets skipped gh to pending"
assert_eq "$(state_is_complete)" "false" "reset gh makes hydrate incomplete"

state_set_phase brew blocked "brew lock" "dinit"
assert_eq "$(state_first_pending)" "brew" "blocked required phase is first pending"

state_set_phase brew ok
state_set_phase gh skipped
assert_eq "$(state_get_blocker)" "" "ok/skipped clears blocker"

printf 'all state algebra tests passed\n'
