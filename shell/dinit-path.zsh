# dinit-path.zsh — PATH only. Safe for ~/.zshenv (login, non-interactive, Cursor agent).
# Do not put prompts, direnv, or zoxide here.

typeset -U path PATH

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PNPM_HOME="${PNPM_HOME:-$HOME/Library/pnpm}"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export MISE_YES="${MISE_YES:-1}"

_dinit_path_dirs=(
  "$CARGO_HOME/bin"
  "$HOME/.local/bin"
  "$HOME/.local/share/mise/shims"
  "$BUN_INSTALL/bin"
  "$PNPM_HOME"
  "/Applications/Cursor.app/Contents/Resources/app/bin"
  "/opt/homebrew/bin"
  "/opt/homebrew/sbin"
  "/usr/local/bin"
)

for _dinit_d in $_dinit_path_dirs; do
  [[ -d "$_dinit_d" ]] || continue
  path=("$_dinit_d" $path)
done
unset _dinit_d _dinit_path_dirs

typeset -U path PATH
export PATH
