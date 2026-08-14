# retry_transient retries a command for transient failures.
# Honors DINIT_RETRY_SLEEP (seconds; 0 skips sleeping) for tests.
retry_transient() {
  local attempts="${1:-3}"
  shift
  local i=1
  local delay=2
  local sleep_s="${DINIT_RETRY_SLEEP:-$delay}"
  local fixed=0
  [[ -n "${DINIT_RETRY_SLEEP+x}" ]] && fixed=1

  if [[ "$attempts" -lt 1 ]]; then
    return 1
  fi

  while true; do
    if "$@"; then
      return 0
    fi
    if [[ "$i" -ge "$attempts" ]]; then
      return 1
    fi
    printf '  retry %s/%s in %ss\n' "$i" "$attempts" "$sleep_s" >&2
    if [[ "$sleep_s" != 0 ]]; then
      sleep "$sleep_s"
    fi
    i=$((i + 1))
    if [[ "$fixed" -eq 0 ]]; then
      delay=$((delay * 2 + 1))
      sleep_s="$delay"
    fi
  done
}
