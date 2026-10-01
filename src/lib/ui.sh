# Output helpers on top of clack.sh.

# step "format" [args...]: printf-style, one clack step per call.
step() {
  local format="${1%\\n}" msg
  shift
  # shellcheck disable=SC2059
  printf -v msg "$format" "$@"
  clack_log_step "$msg"
}

dry() { printf '[DRY-RUN] %s\n' "$*"; }

verbose() { if "$VERBOSE"; then printf '[VERBOSE] %s\n' "$*"; fi; }
