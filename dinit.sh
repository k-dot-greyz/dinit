#!/bin/zsh
# dinit — lazy macOS hydrate for Cursor + modern web + rust.
# One verb: `dinit` = continue. Subcommands: env, sitrep, clone, purge-python.
#
#   dinit                 resume machine hydrate, or territory ritual when inside dev-master
#   dinit env             print export PATH=... for this tab
#   dinit sitrep [-v]     compact tool check (verbose with -v)
#   dinit auth              browser GitHub login + persistent git credentials
#   dinit clone             auth + ssh key + clone dev-master
#   dinit purge-python    pin python 3.14 + purge older
#
# Opt-outs: --no-casks --no-clone --no-purge-old-python --no-path --no-fix-dns --skip-auth

set -euo pipefail

DINIT_ROOT="${0:A:h}"
source "${DINIT_ROOT}/lib/state.sh"

DINIT_MARK_BEGIN="# >>> dinit >>>"
DINIT_MARK_END="# <<< dinit <<<"
SNAPSHOT_DIR="${DINIT_ROOT}/snapshots"
ZSHRC="${HOME}/.zshrc"
ZPROFILE="${HOME}/.zprofile"
ZSHENV="${HOME}/.zshenv"
PROFILE="${HOME}/.profile"
CODE_DIR="${HOME}/Documents/Code"
DEVMASTER_DIR="${CODE_DIR}/dev-master"
DEVMASTER_REPO="${DINIT_DEVMASTER_REPO:-k-dot-greyz/dev-master}"
PYTHON_PIN="${DINIT_PYTHON_PIN:-3.14}"
DINIT_CURRENT_PHASE=""
DINIT_SUDO_KEEPALIVE_PID=""

# defaults ON (opt-out only)
SKIP_AUTH=0
WITH_CASKS=1
CLONE_REPO=1
AUTO_FIX_DNS=1
ADD_PATH=1
PURGE_OLD_PYTHON=1
SITREP_VERBOSE=0

ENV_ONLY=0
DOCTOR=0
SNAPSHOT_ONLY=0
PURGE_ONLY=0
CLONE_ONLY=0
AUTH_ONLY=0
RESUME_MODE=1

for arg in "$@"; do
  case "$arg" in
    --skip-auth) SKIP_AUTH=1 ;;
    --no-casks) WITH_CASKS=0 ;;
    --with-casks) WITH_CASKS=1 ;;
    --no-clone) CLONE_REPO=0 ;;
    --no-purge-old-python) PURGE_OLD_PYTHON=0 ;;
    --no-path) ADD_PATH=0 ;;
    --no-fix-dns) AUTO_FIX_DNS=0 ;;
    --fix-dns) AUTO_FIX_DNS=1 ;;
    -v|--verbose) SITREP_VERBOSE=1 ;;
    env|--env) ENV_ONLY=1; RESUME_MODE=0 ;;
    --snapshot-only) SNAPSHOT_ONLY=1; RESUME_MODE=0 ;;
    clone|--clone) CLONE_ONLY=1; RESUME_MODE=0 ;;
    auth|--auth) AUTH_ONLY=1; RESUME_MODE=0 ;;
    purge-python)
      PURGE_ONLY=1
      RESUME_MODE=0
      PURGE_OLD_PYTHON=1
      ;;
    doctor|--doctor|sitrep|--sitrep) DOCTOR=1; RESUME_MODE=0 ;;
    -h|--help)
      sed -n '2,15p' "$0"
      exit 0
      ;;
    --*) print -u2 "unknown flag: $arg (try --help)"; exit 2 ;;
    *)
      if [[ "$arg" != "" && "$RESUME_MODE" -eq 1 && $# -eq 1 ]]; then
        : # bare `dinit` with no subcommand = resume
      elif [[ "$DOCTOR" -eq 0 && "$ENV_ONLY" -eq 0 ]]; then
        print -u2 "unknown: $arg (try: dinit | dinit auth | dinit env | dinit sitrep | dinit clone)"
        exit 2
      fi
      ;;
  esac
done

autoload -Uz colors && colors

phase() { print -P "\n%F{cyan}==>%f %B$1%b" }
ok()    { print -P "  %F{green}ok%f  $1" }
warn()  { print -P "  %F{yellow}skip%f $1" }
# info prints an informational message.
# print_blocker_footer prints a blocker message and the command to run next.
# write_blocker records a blocked phase, displays its recovery instructions, and exits.
# fail records the current phase as blocked with the supplied message and exits.
# run_phase executes a pending phase and records it as successful.
# need_tty requires an interactive terminal for setup operations.
# ensure_file creates an empty file when the specified file does not exist.
# inject_managed_block inserts or replaces a marked configuration block in a file.
# brew_bin prints the path to the installed Homebrew executable.
# load_brew loads Homebrew's shell environment.
# hydrate_path loads the project's PATH and runtime environment configuration.
# print_env prints shell commands that recreate the hydrated environment.
# stale_path_detect detects whether the current shell has stale setup paths.
# doh_a resolves an A record through DNS-over-HTTPS.
# curl_to downloads a URL to a destination file with retry and timeout handling.
# curl_to_resolved downloads a URL using an explicitly resolved server address.
# host_resolves checks whether a host can be resolved or reached.
# primary_network_service identifies the macOS network service used by the default route.
# hotspot_dns detects DNS servers commonly associated with phone hotspots.
# infer_git_from_gh configures Git identity from the authenticated GitHub account.
# ping_tool reports the availability, version, and path of a command.
# sitrep_compact reports the status of core development tools and Python configuration.
# sitrep_verbose reports the status of additional development tools.
# sitrep reports system, tool, PATH, and hydration status.
# phase_sudo authorizes sudo and starts a keepalive process.
# phase_preflight reports system details and prepares workspace directories.
# phase_net reports network status and optionally repairs hotspot DNS.
# phase_fix_dns configures public DNS resolvers and flushes macOS DNS caches.
# phase_xcode verifies and completes Xcode Command Line Tools setup.
# fetch_homebrew_installer obtains and validates a Homebrew installer script.
# phase_brew installs or refreshes Homebrew and loads its environment.
# phase_bundle installs dependencies declared in the project's Brewfile.
# phase_shell configures managed shell startup hooks.
# phase_git_defaults configures global Git defaults and identity.
# phase_ssh creates and configures the GitHub SSH key and agent integration.
# python314_bin prints the path to the mise-managed Python executable.
# link_python_shims creates user-local Python command shims.
# uninstall_old_mise_pythons removes mise-managed Python versions other than the configured version.
# purge_old_python removes obsolete Python installations and creates system-level Python links.
# pin_python installs, activates, and validates the configured Python version.
# phase_runtimes installs and configures Rust, Python, Node, and package runtimes.
# gh_has_scope checks whether the authenticated GitHub token has a requested scope.
# git_scrub_bad_https_override removes Git URL rewrites that force GitHub SSH URLs to HTTPS.
# github_auth_browser authenticates GitHub through the browser and configures SSH-based Git access.
# phase_gh authenticates GitHub unless authentication was explicitly skipped.
# configure_devmaster_git configures SSH remotes and fetch access for the dev-master repository.
# phase_devmaster clones and configures the dev-master repository.
# write_snapshot saves the current setup state as a timestamped snapshot.
# resume_hydrate resumes setup from the first incomplete phase.
# in_devmaster_tree checks whether the current directory is within the dev-master repository.
# should_run_territory checks whether the project-local setup ritual should run.
# run_territory_ritual executes the dev-master repository's setup ritual.
# maybe_handoff_territory hands control to the project-local setup ritual when available.
# main initializes state and dispatches the requested setup mode.
info()  { print -P "  $1" }

print_blocker_footer() {
  local msg="$1"
  local next="${2:-dinit}"
  print -P "\n%F{red}blocker:%f $msg"
  print -P "%F{cyan}next:%f $next"
}

write_blocker() {
  local phase="$1"
  local msg="$2"
  local next="${3:-dinit}"
  state_set_phase "$phase" "blocked" "$msg" "$next"
  print_blocker_footer "$msg" "$next"
  exit 1
}

fail() {
  write_blocker "${DINIT_CURRENT_PHASE:-unknown}" "$1" "${2:-dinit}"
}

run_phase() {
  local name="$1"
  shift
  local phase_status
  phase_status="$(state_phase_status "$name")"
  [[ "$phase_status" == "ok" ]] && return 0
  DINIT_CURRENT_PHASE="$name"
  "$@"
  state_set_phase "$name" "ok"
}

need_tty() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    print -u2 "dinit wants a real terminal (sudo + brew prompts)."
    print -u2 "Open Terminal.app and run:  dinit"
    exit 1
  fi
}

ensure_file() {
  local f="$1"
  [[ -f "$f" ]] || : > "$f"
}

inject_managed_block() {
  local file="$1"
  local body="$2"
  ensure_file "$file"
  DINIT_MARK_BEGIN="$DINIT_MARK_BEGIN" DINIT_MARK_END="$DINIT_MARK_END" \
    /usr/bin/python3 - "$file" "$body" <<'PY'
import os, sys
path, body = sys.argv[1], sys.argv[2]
begin, end = os.environ["DINIT_MARK_BEGIN"], os.environ["DINIT_MARK_END"]
text = open(path).read()
block = f"{begin}\n{body}\n{end}"
if begin in text and end in text:
    pre, rest = text.split(begin, 1)
    _, post = rest.split(end, 1)
    text = pre + block + post
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += f"\n{block}\n"
open(path, "w").write(text)
PY
}

brew_bin() {
  if [[ -x /opt/homebrew/bin/brew ]]; then print /opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then print /usr/local/bin/brew
  else return 1; fi
}

load_brew() {
  local b
  b="$(brew_bin)" || return 1
  eval "$("$b" shellenv)"
}

hydrate_path() {
  [[ "$ADD_PATH" -eq 1 ]] || return 0
  local pathfile="${DINIT_ROOT}/shell/dinit-path.zsh"
  if [[ -f "$pathfile" ]]; then source "$pathfile"
  else load_brew >/dev/null 2>&1 || true; fi
  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
  if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh 2>/dev/null)" || true
  fi
  export PATH
  rehash 2>/dev/null || hash -r 2>/dev/null || true
}

print_env() {
  hydrate_path
  print -r -- "export PATH=\"${PATH}\""
  print -r -- "export DINIT_ROOT=\"${DINIT_ROOT}\""
  [[ -n "${CARGO_HOME:-}" ]] && print -r -- "export CARGO_HOME=\"${CARGO_HOME}\""
  [[ -n "${MISE_YES:-}" ]] && print -r -- "export MISE_YES=\"${MISE_YES}\""
}

stale_path_detect() {
  hydrate_path
  if command -v gh >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x /opt/homebrew/bin/gh || -x /opt/homebrew/bin/brew ]]; then
    print -P "\n%F{yellow}this tab is stale. paste:%f"
    print -P "eval \"\$(${DINIT_ROOT}/dinit.sh env)\""
    return 1
  fi
  return 0
}

doh_a() {
  local name="$1" json=""
  json="$(curl -fsSL --connect-timeout 8 --resolve cloudflare-dns.com:443:1.1.1.1 \
    -H 'accept: application/dns-json' \
    "https://cloudflare-dns.com/dns-query?name=${name}&type=A" 2>/dev/null)" \
    || json="$(curl -fsSL --connect-timeout 8 --resolve dns.google:443:8.8.8.8 \
      "https://dns.google/resolve?name=${name}&type=A" 2>/dev/null)" \
    || return 1
  print -r -- "$json" | /usr/bin/python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(1)
for a in d.get("Answer") or []:
    if a.get("type") == 1: print(a["data"]); break
else: sys.exit(1)
'
}

curl_to() {
  curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 12 --max-time 60 -o "$1" "$2"
}

curl_to_resolved() {
  local dest="$1" url="$2" host="${${url#https://}%%/*}" ip
  ip="$(doh_a "$host")" || return 1
  [[ -n "$ip" ]] || return 1
  curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 12 --max-time 60 \
    --resolve "${host}:443:${ip}" -o "$dest" "$url"
}

host_resolves() {
  local host="$1"
  dscacheutil -q host -a name "$host" 2>/dev/null | grep -q '^ip_address:' \
    || curl -sI --connect-timeout 5 --max-time 8 "https://${host}" >/dev/null 2>&1
}

primary_network_service() {
  local iface svc
  iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
  if [[ -n "$iface" ]]; then
    svc="$(networksetup -listnetworkserviceorder 2>/dev/null | awk -v iface="$iface" '
      /Hardware Port:/ && index($0, "Device: " iface) {
        sub(/^\(Hardware Port: /, ""); sub(/,.*/, ""); print; exit
      }')"
  fi
  if [[ -z "$svc" ]]; then
    for svc in "Wi-Fi" "iPhone USB" "Ethernet" "USB 10/100/1000 LAN"; do
      networksetup -getinfo "$svc" >/dev/null 2>&1 && { print -r -- "$svc"; return 0; }
    done
    return 1
  fi
  print -r -- "$svc"
}

hotspot_dns() {
  local ns
  ns="$(scutil --dns 2>/dev/null | awk '/nameserver\[0\]/{print $3; exit}')"
  [[ "$ns" == 192.168.43.* || "$ns" == 172.20.10.* || "$ns" == 192.168.137.* ]]
}

infer_git_from_gh() {
  hydrate_path
  load_brew >/dev/null 2>&1 || true
  command -v gh >/dev/null || return 1
  gh auth status >/dev/null 2>&1 || return 1
  local login email name
  login="$(gh api user -q .login 2>/dev/null)" || return 1
  email="$(gh api user -q .email 2>/dev/null)"
  name="$(gh api user -q .name 2>/dev/null)"
  [[ -z "$email" || "$email" == "null" ]] && email="${login}@users.noreply.github.com"
  [[ -z "$name" || "$name" == "null" ]] && name="$login"
  git config --global user.name "$name"
  git config --global user.email "$email"
  ok "git identity from gh: $name <$email>"
}

DINIT_SITREP_MISSING=0

ping_tool() {
  local cmd="$1"; shift
  local -a args=("$@")
  (( $#args == 0 )) && args=(--version)
  if ! command -v "$cmd" >/dev/null 2>&1; then
    print -P "  %F{red}MISS%f  ${cmd}"; DINIT_SITREP_MISSING=1; return 0
  fi
  local bin ver
  bin="$(command -v "$cmd")"
  ver="$("$cmd" "${args[@]}" 2>&1 | head -n 1)" || true
  ver="${ver//$'\n'/ }"
  printf "  \033[32mok\033[0m    %-10s  %s  (%s)\n" "$cmd" "$ver" "$bin"
}

sitrep_compact() {
  ping_tool brew --version
  ping_tool git --version
  ping_tool gh --version
  ping_tool node -v
  ping_tool python3 --version
  ping_tool rustc --version
  ping_tool cursor --version
  if command -v python3 >/dev/null 2>&1; then
    local pyv pybin
    pyv="$(python3 --version 2>&1)"
    pybin="$(command -v python3)"
    case "$pyv" in
      *"${PYTHON_PIN}"*) ok "python ${PYTHON_PIN} honored" ;;
      *) print -P "  %F{yellow}warn%f python is '$pyv' (want ${PYTHON_PIN})"; DINIT_SITREP_MISSING=1 ;;
    esac
    [[ "$pybin" == /usr/bin/python3 ]] && { print -P "  %F{red}miss%f Apple python3 winning PATH"; DINIT_SITREP_MISSING=1; }
  fi
}

sitrep_verbose() {
  ping_tool git-lfs --version
  ping_tool jq --version
  ping_tool rg --version
  ping_tool mise --version
  ping_tool bun --version
  ping_tool pnpm -v
  ping_tool rustup --version
  ping_tool cargo --version
  ping_tool ssh -V
}

sitrep() {
  hydrate_path
  DINIT_SITREP_MISSING=0
  stale_path_detect || DINIT_SITREP_MISSING=1

  phase "sitrep"
  info "user=$USER  $(sw_vers -productVersion)  complete=$(state_is_complete)"

  sitrep_compact
  [[ "$SITREP_VERBOSE" -eq 1 ]] && sitrep_verbose

  local blocker
  blocker="$(state_get_blocker)"
  if [[ -n "$blocker" && "$blocker" != "null" && "$blocker" != "" ]]; then
    print -P "\n%F{red}last blocker:%f $(print -r -- "$blocker" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("message",""))')"
    print -P "%F{cyan}next:%f $(print -r -- "$blocker" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("next","dinit"))')"
  fi

  if [[ "$(state_is_complete)" == "true" ]]; then
    print -P "\n%F{green}hydrate complete.%f You're done."
  fi

  return $DINIT_SITREP_MISSING
}

phase_sudo() {
  phase "sudo (once)"
  if sudo -n true 2>/dev/null; then ok "sudo warm"
  else
    info "password once — python shadow + dns may need it"
    sudo -v || write_blocker "sudo" "sudo required for hydrate" "dinit"
  fi
  if [[ -z "$DINIT_SUDO_KEEPALIVE_PID" ]]; then
    ( while true; do sleep 60; sudo -n true || exit; done ) 2>/dev/null &
    DINIT_SUDO_KEEPALIVE_PID=$!
  fi
}

phase_preflight() {
  phase "preflight"
  info "macOS $(sw_vers -productVersion)  arch=$(uname -m)  user=$USER"
  mkdir -p "$CODE_DIR" "$SNAPSHOT_DIR"
  ok "workspace $CODE_DIR"
}

phase_net() {
  phase "network"
  local ns
  ns="$(scutil --dns 2>/dev/null | awk '/nameserver\[0\]/{print $3; exit}')"
  info "resolver ${ns:-unknown}"
  if hotspot_dns; then
    warn "phone-hotspot DNS detected"
    if [[ "$AUTO_FIX_DNS" -eq 1 ]]; then
      phase_fix_dns
    else
      warn "auto-fix skipped (--no-fix-dns)"
    fi
  fi
  host_resolves github.com && ok "github.com" || warn "github.com unreachable"
}

phase_fix_dns() {
  local svc
  svc="$(primary_network_service)" || write_blocker "net" "could not detect network service" "dinit"
  info "DNS → 1.1.1.1 on $svc"
  sudo networksetup -setdnsservers "$svc" 1.1.1.1 1.0.0.1 8.8.8.8
  dscacheutil -flushcache >/dev/null 2>&1 || true
  sudo killall -HUP mDNSResponder >/dev/null 2>&1 || true
  sleep 1
  ok "DNS updated"
}

phase_xcode() {
  phase "Xcode / CLT"
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install || true
    write_blocker "xcode" "finish CLT install in GUI" "dinit"
  fi
  ok "$(xcode-select -p)"
  if ! git --version >/dev/null 2>&1; then
    sudo xcodebuild -license accept
    sudo xcodebuild -runFirstLaunch || true
  fi
  git --version >/dev/null || write_blocker "xcode" "accept Xcode license in Terminal" "dinit"
  ok "$(git --version)"
}

fetch_homebrew_installer() {
  local dest="$1"
  local vendored="${DINIT_ROOT}/vendor/homebrew-install.sh"
  if [[ -s "$vendored" ]] && head -n 1 "$vendored" | grep -q '^#!'; then
    cp "$vendored" "$dest"; ok "vendored installer"; return 0
  fi
  local url
  for url in \
    "https://github.com/Homebrew/install/raw/HEAD/install.sh" \
    "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  do
    curl_to "$dest" "$url" && [[ -s "$dest" ]] && return 0
    curl_to_resolved "$dest" "$url" && [[ -s "$dest" ]] && return 0
  done
  return 1
}

phase_brew() {
  phase "Homebrew"
  if brew_bin >/dev/null; then
    load_brew; ok "brew $(brew --prefix)"
  else
    local installer
    installer="$(mktemp -t dinit-brew-install)"
    fetch_homebrew_installer "$installer" || {
      rm -f "$installer"
      write_blocker "brew" "Homebrew installer download failed (DNS?)" "dinit"
    }
    head -n 1 "$installer" | grep -q '^#!' || {
      rm -f "$installer"
      write_blocker "brew" "installer download was garbage" "dinit"
    }
    NONINTERACTIVE=1 /bin/bash "$installer"
    rm -f "$installer"
    load_brew || write_blocker "brew" "brew not on PATH after install" "${DINIT_ROOT}/dinit.sh env"
  fi
  export HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
  brew analytics off >/dev/null 2>&1 || true
  brew update --quiet 2>/dev/null || brew update 2>/dev/null || true
  hydrate_path
}

phase_bundle() {
  phase "brew bundle"
  load_brew
  if ! brew bundle install --file="${DINIT_ROOT}/Brewfile" 2>"${SNAPSHOT_DIR}/.brew-bundle.err"; then
    if grep -q 'already locked' "${SNAPSHOT_DIR}/.brew-bundle.err" 2>/dev/null; then
      write_blocker "bundle" "brew lock conflict — wait or kill other brew, then retry" "dinit"
    fi
    write_blocker "bundle" "brew bundle failed — see ${SNAPSHOT_DIR}/.brew-bundle.err" "dinit"
  fi
  hydrate_path
  if [[ "$WITH_CASKS" -eq 1 ]]; then
    brew list --cask orbstack >/dev/null 2>&1 && ok "orbstack already installed" \
      || brew install --cask orbstack 2>/dev/null || warn "orbstack install skipped"
  fi
  ok "bundle done"
}

phase_shell() {
  phase "shell hooks"
  local pathsrc="${DINIT_ROOT}/shell/dinit-path.zsh"
  local src="${DINIT_ROOT}/shell/dinit.zsh"
  [[ -f "$pathsrc" && -f "$src" ]] || write_blocker "shell" "missing shell/*.zsh" "dinit"

  if [[ "$ADD_PATH" -eq 1 ]]; then
    local pathsrc="${DINIT_ROOT}/shell/dinit-path.zsh"
    local pathsh="${DINIT_ROOT}/shell/dinit-path.sh"
    local src="${DINIT_ROOT}/shell/dinit.zsh"
    inject_managed_block "$ZSHENV" "export DINIT_ROOT=\"${DINIT_ROOT}\""$'\n'"[ -f \"$pathsrc\" ] && source \"$pathsrc\""
    inject_managed_block "$ZPROFILE" "export DINIT_ROOT=\"${DINIT_ROOT}\""$'\n'"[ -f \"$pathsrc\" ] && source \"$pathsrc\""
    inject_managed_block "$ZSHRC" "export DINIT_ROOT=\"${DINIT_ROOT}\""$'\n'"[ -f \"$src\" ] && source \"$src\""
    inject_managed_block "$PROFILE" "export DINIT_ROOT=\"${DINIT_ROOT}\""$'\n'"[ -f \"$pathsh\" ] && . \"$pathsh\""
    ok "zshenv/zprofile/zshrc/profile hooks"
  else
    warn "PATH hooks skipped (--no-path)"
  fi
  hydrate_path
}

phase_git_defaults() {
  phase "git defaults"
  git config --global init.defaultBranch main
  git config --global pull.rebase true
  git config --global fetch.prune true
  git config --global push.autoSetupRemote true
  git config --global core.editor "cursor --wait"

  if infer_git_from_gh; then
    return 0
  fi

  if [[ "$SKIP_AUTH" -eq 1 ]]; then
    warn "git identity unset (--skip-auth)"
    return 0
  fi

  if [[ -z "$(git config --global user.name || true)" ]]; then
    local name
    print -n "  git user.name [greyZ]: "
    read -r name
    git config --global user.name "${name:-greyZ}"
  fi
  if [[ -z "$(git config --global user.email || true)" ]]; then
    local email
    print -n "  git user.email: "
    read -r email
    [[ -n "$email" ]] && git config --global user.email "$email"
  fi
  ok "user.name=$(git config --global user.name 2>/dev/null || echo '?')"
}

phase_ssh() {
  phase "ssh key"
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  local key="$HOME/.ssh/id_ed25519"
  [[ -f "$key" ]] || ssh-keygen -t ed25519 -C "${USER}@$(hostname -s)" -f "$key" -N ""
  ok "$key"
  if [[ ! -f "$HOME/.ssh/config" ]]; then
    cat > "$HOME/.ssh/config" <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  AddKeysToAgent yes
  UseKeychain yes
EOF
    chmod 600 "$HOME/.ssh/config"
  fi
  ssh-add --apple-use-keychain "$key" 2>/dev/null || ssh-add "$key" 2>/dev/null || true
}

python314_bin() {
  hydrate_path
  command -v mise >/dev/null && mise which python 2>/dev/null
}

link_python_shims() {
  local bin
  bin="$(python314_bin)" || return 1
  mkdir -p "$HOME/.local/bin"
  ln -sfn "$bin" "$HOME/.local/bin/python"
  ln -sfn "$bin" "$HOME/.local/bin/python3"
  ln -sfn "$bin" "$HOME/.local/bin/python3.14"
}

uninstall_old_mise_pythons() {
  command -v mise >/dev/null || return 0
  local line ver
  mise ls python 2>/dev/null | while IFS= read -r line; do
    ver="$(print -r -- "$line" | awk '{print $2}')"
    [[ -z "$ver" || "$ver" == "Version" ]] && continue
    [[ "$ver" == ${PYTHON_PIN}* ]] && continue
    mise uninstall "python@${ver}" 2>/dev/null || true
  done
}

purge_old_python() {
  load_brew
  local f
  for f in python python3 python@3 python@3.9 python@3.10 python@3.11 python@3.12 python@3.13; do
    brew list --formula "$f" >/dev/null 2>&1 && brew uninstall --ignore-dependencies --formula "$f" 2>/dev/null || true
  done
  uninstall_old_mise_pythons
  local bin
  bin="$(python314_bin)" || write_blocker "runtimes" "python ${PYTHON_PIN} missing" "dinit"
  link_python_shims || true
  if [[ "$(readlink /usr/local/bin/python3 2>/dev/null)" != "$bin" ]]; then
    sudo mkdir -p /usr/local/bin
    sudo ln -sfn "$bin" /usr/local/bin/python3
    sudo ln -sfn "$bin" /usr/local/bin/python
    sudo ln -sfn "$bin" /usr/local/bin/python3.14
  fi
  ok "/usr/local/bin/python3 → 3.14"
}

pin_python() {
  phase "python ${PYTHON_PIN}"
  export MISE_YES=1
  command -v mise >/dev/null || write_blocker "runtimes" "mise missing" "dinit"
  mise use -g "python@${PYTHON_PIN}" || write_blocker "runtimes" "mise python@${PYTHON_PIN} install failed" "dinit"
  eval "$(mise activate zsh 2>/dev/null)" || true
  hydrate_path
  local ver
  ver="$(python3 --version 2>&1)"
  case "$ver" in *"${PYTHON_PIN}"*) ok "$ver" ;; *) write_blocker "runtimes" "wanted ${PYTHON_PIN}, got $ver" "dinit" ;; esac
  link_python_shims || true
  uninstall_old_mise_pythons
  [[ "$PURGE_OLD_PYTHON" -eq 1 ]] && purge_old_python
}

phase_runtimes() {
  phase "runtimes"
  load_brew
  export MISE_YES=1

  if ! command -v rustup >/dev/null 2>&1 && [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
    local rustup_init
    rustup_init="$(mktemp -t dinit-rustup-init)"
    curl --proto '=https' --tlsv1.2 -fsSL -o "$rustup_init" https://sh.rustup.rs \
      || write_blocker "runtimes" "rustup installer download failed" "dinit"
    head -n 1 "$rustup_init" | grep -q '^#!' \
      || { rm -f "$rustup_init"; write_blocker "runtimes" "rustup installer download was garbage" "dinit"; }
    /bin/sh "$rustup_init" -y --default-toolchain stable
    rm -f "$rustup_init"
  fi
  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
  rustup component add clippy rustfmt 2>/dev/null || true
  ok "$(rustc --version)"

  pin_python
  mise use -g node@lts || write_blocker "runtimes" "mise node@lts failed" "dinit"
  eval "$(mise activate zsh 2>/dev/null)" || true
  hydrate_path
  ok "node $(node -v)  python $(python3 --version)"

  if command -v corepack >/dev/null 2>&1; then
    corepack enable 2>/dev/null || true
    corepack prepare pnpm@latest --activate 2>/dev/null || true
    ok "pnpm $(pnpm -v 2>/dev/null || echo '?')"
  fi
  command -v bun >/dev/null && ok "bun $(bun -v)" || warn "bun missing"
}

gh_has_scope() {
  local scope="$1"
  gh auth status 2>&1 | sed -n 's/.*Token scopes: //p' | grep -q "'${scope}'"
}

git_scrub_bad_https_override() {
  local key val
  while IFS= read -r key val; do
    [[ -z "$key" ]] && continue
    # Poison: url.https://github.com/.insteadOf git@github.com:  (SSH → HTTPS)
    if [[ "$key" == *"https://github.com"* ]] || [[ "$val" == "git@github.com:" ]]; then
      git config --global --unset-all "$key" 2>/dev/null || true
      warn "removed bad git config $key (was forcing HTTPS)"
    fi
  done < <(git config --global --get-regexp '^url\..*\.insteadOf$' 2>/dev/null || true)
}

github_auth_browser() {
  phase "GitHub auth (browser → keychain)"
  load_brew
  command -v gh >/dev/null || write_blocker "gh" "gh missing — run dinit first" "dinit"

  export GIT_TERMINAL_PROMPT=0

  local auth_out
  auth_out="$(gh auth status 2>&1 || true)"

  if print -r -- "$auth_out" | grep -q 'token in keyring is invalid'; then
    print -P "\n%F{cyan}━━ Token expired — refresh in browser ━━%f"
    print -P "Your saved GitHub token is stale. Approve a fresh one in the browser.\n"
    gh auth refresh -h github.com -w \
      -s repo -s read:org -s admin:public_key \
      || write_blocker "gh" "token refresh failed" "dinit auth"
  elif ! gh auth status >/dev/null 2>&1; then
    print -P "\n%F{cyan}━━ Browser login ━━%f"
    print -P "A browser window will open. Log in as %B${USER}%b and approve access."
    print -P "%F{yellow}Don't walk away until you see success here.%f\n"
    gh auth login --hostname github.com --git-protocol ssh --web \
      -s repo -s read:org -s admin:public_key \
      || write_blocker "gh" "browser login cancelled or failed" "dinit auth"
  elif ! gh_has_scope repo || ! gh_has_scope admin:public_key; then
    print -P "\n%F{cyan}━━ Token refresh (browser) ━━%f"
    print -P "Your token is missing scopes (repo / ssh keys). Approve in the browser.\n"
    gh auth refresh -h github.com -w \
      -s repo -s read:org -s admin:public_key \
      || write_blocker "gh" "token refresh failed" "dinit auth"
  fi

  ok "$(gh api user -q .login 2>/dev/null) authenticated (keychain)"

  gh auth setup-git
  ok "git → gh credential helper (persistent)"

  git_scrub_bad_https_override
  git config --global url."git@github.com:".insteadOf "https://github.com/"
  ok "all github.com HTTPS URLs rewrite to SSH"

  infer_git_from_gh || true

  if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
    if gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$(hostname -s) dinit" 2>/dev/null; then
      ok "SSH public key on GitHub"
    else
      warn "ssh-key add skipped (may already exist)"
    fi
    ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" 2>/dev/null || true
  fi

  configure_devmaster_git

  print -P "\n%F{green}Auth wired.%f Submodules and git fetch use SSH + keychain — no password prompts."
}

phase_gh() {
  [[ "$SKIP_AUTH" -eq 1 ]] && { warn "gh auth skipped"; return 0; }
  github_auth_browser
}

configure_devmaster_git() {
  [[ -d "$DEVMASTER_DIR/.git" ]] || return 0
  hydrate_path
  command -v gh >/dev/null 2>&1 || return 0
  gh auth status >/dev/null 2>&1 || return 0

  local url
  url="$(git -C "$DEVMASTER_DIR" remote get-url origin 2>/dev/null || true)"
  if [[ "$url" == https://* ]]; then
    info "dev-master origin → SSH"
    git -C "$DEVMASTER_DIR" remote set-url origin "git@github.com:${DEVMASTER_REPO}.git"
  fi

  if [[ -f "$DEVMASTER_DIR/.gitmodules" ]]; then
    info "syncing submodule URLs (HTTPS → SSH)"
    git -C "$DEVMASTER_DIR" submodule sync --recursive 2>/dev/null || true
    ok "submodule remotes synced"
  fi

  export GIT_TERMINAL_PROMPT=0
  if git -C "$DEVMASTER_DIR" fetch origin 2>/dev/null; then
    ok "dev-master fetch ok"
  else
    warn "fetch still failed — run: dinit auth"
  fi
}

phase_devmaster() {
  phase "clone dev-master"
  [[ "$CLONE_REPO" -eq 1 ]] || { warn "clone skipped (--no-clone)"; return 0; }

  if [[ -d "$DEVMASTER_DIR/.git" ]]; then
    ok "already cloned"
    configure_devmaster_git
    return 0
  fi

  hydrate_path
  command -v gh >/dev/null || write_blocker "devmaster" "gh not on PATH" "dinit env"
  gh auth status >/dev/null 2>&1 || write_blocker "devmaster" "not authenticated" "dinit auth"

  if gh repo clone "$DEVMASTER_REPO" "$DEVMASTER_DIR" 2>/dev/null; then
    ok "cloned $DEVMASTER_DIR"
  else
    write_blocker "devmaster" "clone failed — run dinit auth first" "dinit auth"
  fi
  configure_devmaster_git
}

write_snapshot() {
  hydrate_path
  mkdir -p "$SNAPSHOT_DIR"
  local stamp snap latest
  stamp="$(date +%Y%m%dT%H%M%S)"
  snap="${SNAPSHOT_DIR}/${stamp}-state.json"
  latest="${SNAPSHOT_DIR}/latest.json"
  cp "$(state_file)" "$snap" 2>/dev/null || true
  ln -sfn "$(basename "$snap")" "$latest" 2>/dev/null || true
  ok "state → $snap"
}

resume_hydrate() {
  need_tty
  local start
  start="$(state_first_pending)"
  [[ -z "$start" ]] && { sitrep; return 0; }

  info "resuming from phase: $start"

  local -a order=(
    preflight sudo net xcode brew bundle shell git_defaults ssh runtimes gh devmaster snapshot
  )
  local p run=0
  for p in $order; do
    [[ "$run" -eq 1 || "$p" == "$start" ]] && run=1
    [[ "$run" -eq 0 ]] && continue
    case "$p" in
      preflight) run_phase preflight phase_preflight ;;
      sudo)      run_phase sudo phase_sudo ;;
      net)       run_phase net phase_net ;;
      xcode)     run_phase xcode phase_xcode ;;
      brew)      run_phase brew phase_brew ;;
      bundle)    run_phase bundle phase_bundle ;;
      shell)     run_phase shell phase_shell ;;
      git_defaults) run_phase git_defaults phase_git_defaults ;;
      ssh)       run_phase ssh phase_ssh ;;
      runtimes)  run_phase runtimes phase_runtimes ;;
      gh)        run_phase gh phase_gh ;;
      devmaster) run_phase devmaster phase_devmaster ;;
      snapshot)  run_phase snapshot write_snapshot ;;
    esac
  done

  sitrep || true
  if [[ "$(state_is_complete)" == "true" ]]; then
    print -P "\n%F{green}hydrate complete.%f"
    print -P "this tab:  eval \"\$(${DINIT_ROOT}/dinit.sh env)\""
    maybe_handoff_territory
  fi
}

in_devmaster_tree() {
  local cwd="${PWD:A}"
  local root="${DEVMASTER_DIR:A}"
  [[ -d "$root/.git" ]] || return 1
  [[ "$cwd" == "$root" || "$cwd" == "$root"/* ]]
}

should_run_territory() {
  [[ "$(state_is_complete)" == "true" ]] || return 1
  in_devmaster_tree
}

run_territory_ritual() {
  local ritual="${DEVMASTER_DIR}/dinit.sh"
  [[ -f "$ritual" ]] || {
    warn "territory dinit missing at $ritual"
    return 1
  }
  info "handoff → territory ritual"
  exec bash "$ritual"
}

maybe_handoff_territory() {
  [[ -d "$DEVMASTER_DIR/.git" ]] || return 0
  [[ -f "${DEVMASTER_DIR}/dinit.sh" ]] || return 0
  run_territory_ritual
}

main() {
  state_init
  seed_state_from_system

  if [[ "$ENV_ONLY" -eq 1 ]]; then
    print_env
    exit 0
  fi

  if [[ "$DOCTOR" -eq 1 ]]; then
    sitrep
    exit $?
  fi

  if [[ "$SNAPSHOT_ONLY" -eq 1 ]]; then
    write_snapshot
    exit 0
  fi

  if [[ "$PURGE_ONLY" -eq 1 ]]; then
    need_tty
    hydrate_path
    load_brew
    pin_python
    sitrep || true
    exit 0
  fi

  if [[ "$AUTH_ONLY" -eq 1 ]]; then
    need_tty
    hydrate_path
    phase_ssh
    github_auth_browser
    state_set_phase gh ok
    [[ -d "$DEVMASTER_DIR/.git" ]] && state_set_phase devmaster ok
    sitrep || true
    print -P "\n%F{cyan}try submodule:%f"
    print -P "  cd ${DEVMASTER_DIR} && git submodule update --init dex/09-repos/mcp-config"
    exit 0
  fi

  if [[ "$CLONE_ONLY" -eq 1 ]]; then
    need_tty
    hydrate_path
    load_brew
    phase_ssh
    github_auth_browser
    phase_devmaster
    [[ -d "$DEVMASTER_DIR/.git" ]] && state_set_phase devmaster ok
    gh auth status >/dev/null 2>&1 && state_set_phase gh ok
    write_snapshot 2>/dev/null || state_set_phase snapshot ok
    sitrep || true
    if [[ -d "$DEVMASTER_DIR/.git" ]]; then
      maybe_handoff_territory || true
    fi
    exit 0
  fi

  if [[ "$RESUME_MODE" -eq 1 && $# -eq 0 ]] && should_run_territory; then
    run_territory_ritual
  fi

  resume_hydrate
}

main "$@"
