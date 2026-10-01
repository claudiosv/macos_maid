# Defaults, overridden by bashly's parsed flags below
DO_UPDATES=true
CLEAR_LAUNCHPAD=true
CLEAR_IOS=false
CLEAR_CHROME=false
CLEAR_ELECTRON_APP_CACHES=false
UPDATE_MAMBA_ENVS=false
DRY_RUN=false
VERBOSE=false
LOG_OUTPUT=false

EXCLUDE_FORMULAE=()
EXCLUDE_CASKS=(font-comic-neue font-open-sans font-roboto)
MAMBA_SKIP_ENVS=()

LOG_DIR="${HOME}/Library/Logs/MacCleanup"
LOG_FILE="${LOG_DIR}/cleanup_$(date +%Y%m%d_%H%M%S).log"

[[ -n ${args["--no-updates"]:-} ]] && DO_UPDATES=false
[[ -n ${args["--launchpad"]:-} ]] && CLEAR_LAUNCHPAD=true
[[ -n ${args["--chrome"]:-} ]] && CLEAR_CHROME=true
[[ -n ${args["--electron"]:-} ]] && CLEAR_ELECTRON_APP_CACHES=true
[[ -n ${args["--ios"]:-} ]] && CLEAR_IOS=true
[[ -n ${args["--mamba"]:-} ]] && UPDATE_MAMBA_ENVS=true
[[ -n ${args["--dry-run"]:-} ]] && DRY_RUN=true
[[ -n ${args["--verbose"]:-} ]] && VERBOSE=true
[[ -n ${args["--log"]:-} ]] && LOG_OUTPUT=true

# Fail on undeclared variable
set -o nounset

clack_intro "macOS Maid"
verbose "Starting macOS Maid in verbose mode..."

sudo_keepalive
setup_logging

bytes_free_before="$(free_bytes)"

stage_macos_updates
stage_brew
stage_shell_tools
stage_tex
stage_mamba
stage_language_packages
stage_purge
stage_dev_cleanup
stage_browsers
stage_ios
stage_resets

if "$DRY_RUN"; then
  clack_outro "Dry-run complete. No files were actually deleted."
else
  delta=$(($(free_bytes) - bytes_free_before))
  if "$LOG_OUTPUT"; then step "Detailed log saved to: %s" "$LOG_FILE"; fi
  clack_outro "Cleanup success! $(bytes_to_human "$delta")"
fi
