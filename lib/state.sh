# shellcheck shell=bash
# state_file prints the path to the persistent state file.

state_file() {
  print -r -- "${DINIT_ROOT}/state.json"
}

# state_init creates the dinit state directory and initializes its state file when absent.
state_init() {
  local sf
  sf="$(state_file)"
  mkdir -p "${DINIT_ROOT}"
  if [[ ! -f "$sf" ]]; then
    DINIT_ROOT="$DINIT_ROOT" /usr/bin/python3 - "$sf" <<'PY'
import json, os, sys
from datetime import datetime, timezone
root = os.environ["DINIT_ROOT"]
phases = [
    "preflight", "sudo", "net", "xcode", "brew", "bundle",
    "shell", "git_defaults", "ssh", "runtimes", "gh", "devmaster", "snapshot",
]
state = {
    "schema": "dinit.state.v1",
    "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "complete": False,
    "phases": {p: "pending" for p in phases},
    "blocker": None,
}
with open(sys.argv[1], "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
PY
  fi
}

# state_read initializes the state file if needed and prints its contents as compact JSON.
state_read() {
  state_init
  /usr/bin/python3 - "$(state_file)" <<'PY'
import json, sys
print(json.dumps(json.load(open(sys.argv[1]))))
PY
}

# state_phase_status prints the current status of a setup phase, defaulting to `pending` when no status is recorded.
state_phase_status() {
  local phase="$1"
  state_read | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('phases',{}).get(sys.argv[1],'pending'))" "$phase"
}

# state_set_phase updates a phase status, records relevant blocker details, and recalculates overall completion.
state_set_phase() {
  local phase="$1"
  local phase_status="$2"
  local blocker_msg="${3:-}"
  local next_cmd="${4:-dinit}"
  DINIT_ROOT="$DINIT_ROOT" /usr/bin/python3 - "$(state_file)" "$phase" "$phase_status" "$blocker_msg" "$next_cmd" <<'PY'
import json, sys
from datetime import datetime, timezone
path, phase, status, msg, nxt = sys.argv[1:6]
with open(path) as f:
    state = json.load(f)
state["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
state.setdefault("phases", {})[phase] = status
if status == "ok":
    state["blocker"] = None
elif status in ("failed", "blocked") and msg:
    state["blocker"] = {"phase": phase, "message": msg, "next": nxt}
done = all(v == "ok" for v in state["phases"].values())
state["complete"] = done
with open(path, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
PY
}

# state_first_pending prints the first setup phase that is not marked "ok", following the predefined phase order.
state_first_pending() {
  state_init
  /usr/bin/python3 - "$(state_file)" <<'PY'
import json, sys
order = [
    "preflight", "sudo", "net", "xcode", "brew", "bundle",
    "shell", "git_defaults", "ssh", "runtimes", "gh", "devmaster", "snapshot",
]
with open(sys.argv[1]) as f:
    d = json.load(f)
phases = d.get("phases", {})
for p in order:
    if phases.get(p) != "ok":
        print(p)
        break
PY
}

# state_is_complete prints whether all setup phases are complete.
state_is_complete() {
  state_read | /usr/bin/python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('complete') else 'false')"
}

# state_get_blocker prints the current state blocker as JSON, or an empty string when no blocker is set.
state_get_blocker() {
  state_read | /usr/bin/python3 -c "import json,sys; b=json.load(sys.stdin).get('blocker'); print(json.dumps(b) if b else '')"
}

# seed_state_from_system marks pending setup phases complete when their setup invariants are already satisfied. Existing non-pending statuses are never overwritten. Subsequent calls leave already seeded state unchanged.
seed_state_from_system() {
  DINIT_ROOT="$DINIT_ROOT" ZSHRC="$ZSHRC" DEVMASTER_DIR="$DEVMASTER_DIR" PYTHON_PIN="$PYTHON_PIN" \
    /usr/bin/python3 - "$(state_file)" <<'PY'
import glob
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone

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
brewfile = os.path.join(dinit_root, "Brewfile")
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
state["complete"] = all(v == "ok" for v in phases.values())
with open(path, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
PY
}
