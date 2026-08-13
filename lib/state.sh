# shellcheck shell=bash
# dinit state helpers — sourced by dinit.sh (zsh-compatible)

state_file() {
  print -r -- "${DINIT_ROOT}/state.json"
}

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

state_read() {
  state_init
  /usr/bin/python3 - "$(state_file)" <<'PY'
import json, sys
print(json.dumps(json.load(open(sys.argv[1]))))
PY
}

state_phase_status() {
  local phase="$1"
  state_read | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('phases',{}).get(sys.argv[1],'pending'))" "$phase"
}

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

state_is_complete() {
  state_read | /usr/bin/python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('complete') else 'false')"
}

state_get_blocker() {
  state_read | /usr/bin/python3 -c "import json,sys; b=json.load(sys.stdin).get('blocker'); print(json.dumps(b) if b else '')"
}

seed_state_from_system() {
  DINIT_ROOT="$DINIT_ROOT" ZSHRC="$ZSHRC" DEVMASTER_DIR="$DEVMASTER_DIR" PYTHON_PIN="$PYTHON_PIN" \
    /usr/bin/python3 - "$(state_file)" <<'PY'
import json, os, shutil, subprocess, sys
from datetime import datetime, timezone

path = sys.argv[1]
with open(path) as f:
    state = json.load(f)
if state.get("seeded"):
    sys.exit(0)

def ok(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, timeout=5).returncode == 0
    except Exception:
        return False

def which(name):
    return shutil.which(name)

phases = state.setdefault("phases", {})
home = os.path.expanduser("~")
zshrc = os.environ.get("ZSHRC", home + "/.zshrc")
devmaster = os.environ.get("DEVMASTER_DIR", home + "/Documents/Code/dev-master")
pin = os.environ.get("PYTHON_PIN", "3.14")

phases["preflight"] = "ok"
if ok(["git", "--version"]):
    phases["xcode"] = "ok"
if os.path.isdir("/opt/homebrew") or os.path.isdir("/usr/local/Homebrew"):
    phases["brew"] = "ok"
if which("gh") and which("rg") and which("mise"):
    phases["bundle"] = "ok"
if os.path.isfile(zshrc) and "dinit" in open(zshrc).read():
    phases["shell"] = "ok"
if ok(["git", "config", "--global", "user.name"]):
    phases["git_defaults"] = "ok"
if os.path.isfile(home + "/.ssh/id_ed25519"):
    phases["ssh"] = "ok"
py_ok = False
if which("python3"):
    try:
        p = subprocess.run(["python3", "--version"], capture_output=True, text=True, timeout=5)
        py_ok = pin in (p.stdout or p.stderr or "")
    except Exception:
        pass
if which("node") and which("rustc") and py_ok:
    phases["runtimes"] = "ok"
if os.path.isdir(devmaster + "/.git"):
    phases["devmaster"] = "ok"
if which("gh") and ok(["gh", "auth", "status"]):
    phases["gh"] = "ok"

state["seeded"] = True
state["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
state["complete"] = all(v == "ok" for v in phases.values())
with open(path, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
PY
}
