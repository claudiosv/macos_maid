# Sudo keep-alive, logging, disk-space accounting.

sudo_keepalive() {
  require_cmd sudo || return 0
  step "Requesting administrative privileges..."
  sudo -v
  (
    while true; do
      sudo -n -v 2>/dev/null
      sleep 60
      kill -0 "$$" || exit
    done 2>/dev/null
  ) >/dev/null 2>&1 &
}

setup_logging() {
  "$LOG_OUTPUT" || return 0
  mkdir -p "$LOG_DIR"
  if ! "$DRY_RUN"; then
    # Redirect all stdout/stderr to tee to log file AND terminal
    exec > >(tee -a "$LOG_FILE") 2>&1
    step "Logging output to: %s" "$LOG_FILE"
  fi
}

free_bytes() {
  local kib
  kib="$(df -kP / | awk 'NR==2{print $4}')"
  echo $((kib * 1024))
}

bytes_to_human() {
  local delta="${1:-0}" abs i frac
  local -a UNITS=("Bytes" "KiB" "MiB" "GiB" "TiB")

  abs=$((delta < 0 ? -delta : delta))
  i=0
  frac=0

  while ((abs > 1024 && i < ${#UNITS[@]} - 1)); do
    frac=$((abs % 1024 * 100 / 1024))
    abs=$((abs / 1024))
    ((++i))
  done

  if ((delta >= 0)); then
    printf '%s.%02d %s freed up...\n' "$abs" "$frac" "${UNITS[i]}"
  else
    printf '%s.%02d %s consumed :(\n' "$abs" "$frac" "${UNITS[i]}"
  fi
}
