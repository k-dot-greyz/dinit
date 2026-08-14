# shellcheck shell=bash
# state helpers — catalog-backed JSON state for dinit.

: "${DINIT_LIB:=${DINIT_ROOT}/lib}"
DINIT_STATE_PY="${DINIT_LIB}/dinit_state.py"

# state_file prints the path to the persistent state file.
state_file() {
  print -r -- "${DINIT_ROOT}/state.json"
}

_state_py() {
  /usr/bin/python3 "$DINIT_STATE_PY" "$@"
}

# state_init creates the dinit state directory and initializes its state file when absent.
state_init() {
  mkdir -p "${DINIT_ROOT}"
  _state_py init "$(state_file)"
}

# state_read initializes the state file if needed and prints its contents as compact JSON.
state_read() {
  state_init
  _state_py dump "$(state_file)"
}

# state_phase_status prints the current status of a setup phase, defaulting to `pending` when no status is recorded.
state_phase_status() {
  local phase="$1"
  state_init
  _state_py get "$(state_file)" "$phase"
}

# state_phase_kind prints the catalog kind for a phase (required, session, human).
state_phase_kind() {
  _state_py kind "$1"
}

# state_phase_skippable prints true when a phase may be persisted as skipped.
state_phase_skippable() {
  _state_py skippable "$1"
}

# state_phase_apply prints the shell function that applies a phase.
state_phase_apply() {
  _state_py apply "$1"
}

# state_phase_ids prints catalog phase ids in order, one per line.
state_phase_ids() {
  _state_py ids
}

# state_catalog_table prints id, kind, status, and retry class for each phase.
state_catalog_table() {
  state_init
  _state_py table "$(state_file)"
}

# state_set_phase updates a phase status, records relevant blocker details, and recalculates overall completion.
state_set_phase() {
  local phase="$1"
  local phase_status="$2"
  local blocker_msg="${3:-}"
  local next_cmd="${4:-dinit}"
  state_init
  _state_py set "$(state_file)" "$phase" "$phase_status" "$blocker_msg" "$next_cmd"
}

# state_skip_phase persists a skippable phase as skipped. Non-skippable phases fail.
state_skip_phase() {
  local phase="$1"
  local msg="${2:-skipped}"
  local next_cmd="${3:-dinit}"
  state_init
  _state_py skip "$(state_file)" "$phase" "$msg" "$next_cmd"
}

# state_reset_phase sets a phase back to pending so the next resume retries it.
state_reset_phase() {
  local phase="$1"
  state_init
  _state_py reset "$(state_file)" "$phase"
}

# state_first_pending prints the first non-session phase that is not ok or skipped.
state_first_pending() {
  state_init
  _state_py first-pending "$(state_file)"
}

# state_is_complete prints whether all required and human phases are ok or skipped.
state_is_complete() {
  state_init
  _state_py is-complete "$(state_file)"
}

# state_get_blocker prints the current state blocker as JSON, or an empty string when no blocker is set.
state_get_blocker() {
  state_init
  _state_py blocker "$(state_file)"
}

# seed_state_from_system marks pending setup phases complete when their setup invariants are already satisfied. Existing non-pending statuses are never overwritten. Subsequent calls leave already seeded state unchanged.
seed_state_from_system() {
  state_init
  DINIT_ROOT="$DINIT_ROOT" DINIT_LIB="$DINIT_LIB" ZSHRC="$ZSHRC" DEVMASTER_DIR="$DEVMASTER_DIR" PYTHON_PIN="$PYTHON_PIN" \
    /usr/bin/python3 - "$(state_file)" <<'PY'
import glob
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.environ["DINIT_LIB"])
from dinit_state import compute_complete

path = sys.argv[1]
with open(path) as f:
    state = json.load(f)
if state.get("seeded"):
    sys.exit(0)

def ok(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, timeout=8).returncode == 0
    except Exception:
        return False

def which(name):
    return shutil.which(name)

def git_config(key):
    try:
        p = subprocess.run(
            ["git", "config", "--global", key],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return p.stdout.strip() if p.returncode == 0 else ""
    except Exception:
        return ""

def file_contains(path, needle):
    try:
        return os.path.isfile(path) and needle in open(path).read()
    except Exception:
        return False

phases = state.setdefault("phases", {})
home = os.path.expanduser("~")
dinit_root = os.environ.get("DINIT_ROOT", home + "/Documents/Code/dinit")
zshrc = os.environ.get("ZSHRC", home + "/.zshrc")
devmaster = os.environ.get("DEVMASTER_DIR", home + "/Documents/Code/dev-master")
code_dir = os.path.dirname(devmaster) or home + "/Documents/Code"
pin = os.environ.get("PYTHON_PIN", "3.14")
dinit_home = os.environ.get("DINIT_HOME") or os.path.dirname(os.environ.get("DINIT_LIB", dinit_root))
brewfile = os.path.join(dinit_home, "Brewfile")
snapshot_dir = os.path.join(dinit_root, "snapshots")

def maybe_mark(phase, condition):
    if phases.get(phase, "pending") != "pending":
        return
    if condition:
        phases[phase] = "ok"

maybe_mark(
    "preflight",
    os.path.isdir(code_dir) and os.path.isdir(snapshot_dir),
)
maybe_mark(
    "xcode",
    ok(["xcode-select", "-p"]) and ok(["git", "--version"]),
)
maybe_mark(
    "brew",
    which("brew") is not None and ok(["brew", "--prefix"]),
)
maybe_mark(
    "bundle",
    os.path.isfile(brewfile) and ok(["brew", "bundle", "check", "--file", brewfile]),
)
maybe_mark(
    "shell",
    file_contains(zshrc, "# >>> dinit >>>")
    and file_contains(zshrc, "dinit.zsh"),
)
maybe_mark(
    "git_defaults",
    bool(git_config("user.name"))
    and git_config("init.defaultBranch") == "main"
    and git_config("pull.rebase") == "true",
)
maybe_mark(
    "ssh",
    os.path.isfile(home + "/.ssh/id_ed25519")
    and file_contains(home + "/.ssh/config", "github.com"),
)
py_ok = False
if which("python3"):
    try:
        p = subprocess.run(["python3", "--version"], capture_output=True, text=True, timeout=5)
        py_ok = pin in (p.stdout or p.stderr or "")
    except Exception:
        pass
maybe_mark(
    "runtimes",
    which("rustc") is not None and which("node") is not None and py_ok,
)
maybe_mark("devmaster", os.path.isdir(devmaster + "/.git"))
maybe_mark("gh", which("gh") is not None and ok(["gh", "auth", "status"]))
maybe_mark(
    "snapshot",
    bool(glob.glob(os.path.join(snapshot_dir, "*-state.json"))),
)

state["seeded"] = True
state["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
state["complete"] = compute_complete(phases)
with open(path, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
PY
}
