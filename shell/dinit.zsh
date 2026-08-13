# dinit.zsh — interactive shell + lazy `dinit` wrapper.
# PATH lives in dinit-path.zsh (also hooked from ~/.zshenv).

: "${DINIT_ROOT:="${${(%):-%x}:A:h:h}"}"

source "${DINIT_ROOT}/shell/dinit-path.zsh"

[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh 2>/dev/null)" || true
fi

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

export EDITOR="${EDITOR:-cursor}"
export VISUAL="${VISUAL:-$EDITOR}"

typeset -U path PATH
export PATH

# Lazy wrapper: after every dinit run, infect THIS tab's PATH
dinit() {
  local rc=0
  "${DINIT_ROOT}/dinit.sh" "$@" || rc=$?
  if [[ "${1:-}" != "env" && "${1:-}" != "--env" ]]; then
    eval "$("${DINIT_ROOT}/dinit.sh" env 2>/dev/null)" && hash -r 2>/dev/null || true
  fi
  return $rc
}
