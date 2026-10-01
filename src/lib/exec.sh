# Execution & deletion wrappers; honor DRY_RUN and VERBOSE.

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

safe_rm() {
  if "$DRY_RUN"; then
    dry "Would remove: $*"
  elif "$VERBOSE"; then
    verbose "Removing paths for: $*"
    rm -rfv "$@" || true
  else
    rm -rf "$@" >/dev/null 2>&1 || true
  fi
}

safe_sudo_rm() {
  if "$DRY_RUN"; then
    dry "Would sudo remove: $*"
  elif "$VERBOSE"; then
    verbose "Sudo removing paths for: $*"
    sudo rm -rfv "$@" || true
  else
    sudo rm -rf "$@" >/dev/null 2>&1 || true
  fi
}

# run_cmd [--show] [--bg] cmd...: output is hidden unless --show or --verbose.
run_cmd() {
  local show_output=false
  local run_in_bg=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --show)
        show_output=true
        shift
        ;;
      --bg)
        run_in_bg=true
        shift
        ;;
      *) break ;; # Stop parsing once we hit the actual command
    esac
  done

  if "$DRY_RUN"; then
    if "$run_in_bg"; then
      dry "Would execute in background: $*"
    else
      dry "Would execute: $*"
    fi
  elif "$VERBOSE"; then
    if "$run_in_bg"; then
      verbose "Executing in background: $*"
      "$@" &
    else
      verbose "Executing: $*"
      "$@" || true
    fi
  elif "$show_output"; then
    if "$run_in_bg"; then
      "$@" &
    else
      "$@" || true
    fi
  else
    if "$run_in_bg"; then
      "$@" >/dev/null 2>&1 &
    else
      "$@" >/dev/null 2>&1 || true
    fi
  fi
}
