#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# state.sh uses zsh's print builtin; shim it for bash-based CI.
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
ZSHRC="$TMP/.zshrc"
DEVMASTER_DIR="$TMP/dev-master"
PYTHON_PIN="3.14"
export DINIT_ROOT ZSHRC DEVMASTER_DIR PYTHON_PIN

mkdir -p "$DINIT_ROOT" "$TMP/snapshots" "$TMP/Code"
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

state_init
seed_state_from_system

assert_eq "$(state_phase_status brew)" "pending" "blocked-like phase stays pending without brew"
assert_eq "$(python3 -c "import json; print(json.load(open('$DINIT_ROOT/state.json')).get('seeded'))")" "True" "seeded flag is set"

python3 - "$DINIT_ROOT/state.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    state = json.load(f)
state["seeded"] = False
state["phases"]["brew"] = "blocked"
state["phases"]["xcode"] = "failed"
state["blocker"] = {"phase": "brew", "message": "test", "next": "dinit"}
with open(path, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
PY

seed_state_from_system

assert_eq "$(state_phase_status brew)" "blocked" "blocked phase is not overwritten"
assert_eq "$(state_phase_status xcode)" "failed" "failed phase is not overwritten"

mkdir -p "$DINIT_ROOT/snapshots" "$TMP/Code"
DEVMASTER_DIR="$TMP/Code/dev-master"
export DEVMASTER_DIR
python3 - "$DINIT_ROOT/state.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    state = json.load(f)
state["seeded"] = False
state["phases"]["preflight"] = "pending"
with open(path, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
PY

seed_state_from_system
assert_eq "$(state_phase_status preflight)" "ok" "preflight seeds when workspace dirs exist"

python3 - "$DINIT_ROOT/state.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    state = json.load(f)
state["seeded"] = True
state["phases"]["net"] = "pending"
with open(path, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
PY

seed_state_from_system
assert_eq "$(state_phase_status net)" "pending" "already-seeded state is left unchanged"

printf 'all seed_state_from_system tests passed\n'
