# dinit-path.sh — POSIX PATH for bash/login shells (env-doctor, dev-master dinit.sh).
# zsh uses dinit-path.zsh; keep both in sync.

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PNPM_HOME="${PNPM_HOME:-$HOME/Library/pnpm}"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export MISE_YES="${MISE_YES:-1}"
export DINIT_ROOT="${DINIT_ROOT:-$HOME/Documents/Code/dinit}"

_prepend_path() {
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

[[ -d "$CARGO_HOME/bin" ]] && _prepend_path "$CARGO_HOME/bin"
[[ -d "$HOME/.local/bin" ]] && _prepend_path "$HOME/.local/bin"
[[ -d "$HOME/.local/share/mise/shims" ]] && _prepend_path "$HOME/.local/share/mise/shims"
[[ -d "$BUN_INSTALL/bin" ]] && _prepend_path "$BUN_INSTALL/bin"
[[ -d "$PNPM_HOME" ]] && _prepend_path "$PNPM_HOME"
[[ -d /Applications/Cursor.app/Contents/Resources/app/bin ]] && \
  _prepend_path /Applications/Cursor.app/Contents/Resources/app/bin
[[ -d /opt/homebrew/bin ]] && _prepend_path /opt/homebrew/bin
[[ -d /opt/homebrew/sbin ]] && _prepend_path /opt/homebrew/sbin

export PATH
