# If env ERR_EXIT==1, script exits on failed command
if [[ ${ERR_EXIT-0} == "1" ]]; then set -o errexit; fi

# If env PIPE_FAIL==1, script exits on failed pipe
if [[ ${PIPE_FAIL-0} == "1" ]]; then set -o pipefail; fi

# If env TRACE==1, show script trace
if [[ ${TRACE-0} == "1" ]]; then set -o xtrace; fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: macOS Maid is designed for macOS only." >&2
  exit 1
fi

enable_auto_colors

# Run relative to the script's own directory
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$script_dir" || exit
