#!/usr/bin/env bash

inspect_args

# If env ERR_EXIT==1, script exits on failed command
if [[ ${ERR_EXIT-0} == "1" ]]; then set -o errexit; fi

# If env PIPE_FAIL==1, script exits on failed pipe
if [[ ${PIPE_FAIL-0} == "1" ]]; then set -o pipefail; fi

# If env TRACE==1, show script trace
if [[ ${TRACE-0} == "1" ]]; then set -o xtrace; fi

# Resolve script directory and cd into it
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "${script_dir}" || exit

# -----------------------------
# Flags & Variables
# -----------------------------
DO_UPDATES=true
CLEAR_LAUNCHPAD=true
CLEAR_IOS=false
DRY_RUN=false
VERBOSE=false
CLEAR_CHROME=false
LOG_OUTPUT=false
UPDATE_MAMBA_ENVS=false

EXCLUDE_FORMULAE=()
EXCLUDE_CASKS=(font-comic-neue font-open-sans)
MAMBA_SKIP_ENVS=()

LOG_DIR="${HOME}/Library/Logs/MacCleanup"
LOG_FILE="${LOG_DIR}/cleanup_$(date +%Y%m%d_%H%M%S).log"

# Override defaults based on Bashly's parsed flags
[[ -n ${args[--no-updates]} ]] && DO_UPDATES=false
[[ -n ${args[--launchpad]} ]] && CLEAR_LAUNCHPAD=true
[[ -n ${args[--chrome]} ]] && CLEAR_CHROME=true
[[ -n ${args[--ios]} ]] && CLEAR_IOS=true
[[ -n ${args[--mamba]} ]] && UPDATE_MAMBA_ENVS=true
[[ -n ${args[--dry-run]} ]] && DRY_RUN=true
[[ -n ${args[--verbose]} ]] && VERBOSE=true
[[ -n ${args[--log]} ]] && LOG_OUTPUT=true

# Fail on undeclared variable
set -o nounset

# Your script logic continues here...
if [[ "$VERBOSE" == true ]]; then
  echo "Starting macOS Maid in verbose mode..."
fi

# -----------------------------
# Sudo keep-alive (Run First)
# -----------------------------
if command -v sudo >/dev/null 2>&1; then
  printf "✨ Requesting administrative privileges...\n"
  sudo -v
  (
    while true; do
      sudo -n true
      sleep 60
      kill -0 "$$" || exit
    done 2>/dev/null
  ) &
fi

# -----------------------------
# Centralized Logging Setup
# -----------------------------
if ${LOG_OUTPUT}; then
  mkdir -p "${LOG_DIR}"
  if ! ${DRY_RUN}; then
    # Redirect all stdout/stderr to tee to log file AND terminal
    exec > >(tee -a "${LOG_FILE}") 2>&1
    printf "✨ Logging output to: %s\n" "${LOG_FILE}"
  fi
fi

# -----------------------------
# Helpers
# -----------------------------
sparkle() {
  local format="$1"
  shift # Shift removes the first argument ($1), leaving only the variables in $@

  # We strip any trailing '\n' the user might accidentally pass
  # to prevent double-spacing, then wrap it in our standard spacing.
  format="${format%\\n}"

  # shellcheck disable=SC2059
  printf "✨ ${format}\n" "$@"
  # printf "\n✨ %s\n" "$format" "$@"
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
    ((i++))
  done

  if ((delta >= 0)); then
    printf '%s.%02d %s freed up...\n' "${abs}" "${frac}" "${UNITS[i]}"
  else
    printf '%s.%02d %s consumed :(\n' "${abs}" "${frac}" "${UNITS[i]}"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# -----------------------------
# Execution & Deletion Wrappers
# -----------------------------
safe_rm() {
  if ${DRY_RUN}; then
    printf '[DRY-RUN] Would remove: %s\n' "$*"
  elif ${VERBOSE}; then
    printf '[VERBOSE] Removing paths for: %s\n' "$*"
    rm -rfv "$@" || true
  else
    rm -rf "$@" >/dev/null 2>&1 || true
  fi
}

safe_sudo_rm() {
  if ${DRY_RUN}; then
    printf '[DRY-RUN] Would sudo remove: %s\n' "$*"
  elif ${VERBOSE}; then
    printf '[VERBOSE] Sudo removing paths for: %s\n' "$*"
    sudo rm -rfv "$@" || true
  else
    sudo rm -rf "$@" >/dev/null 2>&1 || true
  fi
}

run_cmd() {
  local show_output=false
  local run_in_bg=false

  # Extract our custom flags before executing the real command
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

  if ${DRY_RUN}; then
    if ${run_in_bg}; then
      printf '[DRY-RUN] Would execute in background: %s\n' "$*"
    else
      printf '[DRY-RUN] Would execute: %s\n' "$*"
    fi
  elif ${VERBOSE}; then
    if ${run_in_bg}; then
      printf '[VERBOSE] Executing in background: %s\n' "$*"
      "$@" &
    else
      printf '[VERBOSE] Executing: %s\n' "$*"
      "$@" || true
    fi
  elif ${show_output}; then
    if ${run_in_bg}; then
      "$@" &
    else
      "$@" || true
    fi
  else
    # Silent execution
    if ${run_in_bg}; then
      "$@" >/dev/null 2>&1 &
    else
      "$@" >/dev/null 2>&1 || true
    fi
  fi
}

clean_safari_completely() {
  sparkle "Deep Cleaning Safari..."

  local was_killed=false

  # 1. Safely close Safari
  # We use -x (exact match) so we don't accidentally kill "SafariBookmarksSyncAgent"
  if pgrep -x "Safari" >/dev/null; then
    was_killed=true
    if ! ${DRY_RUN}; then
      if ${VERBOSE}; then printf '[VERBOSE] Closing Safari...\n'; fi
      # Using osascript for Safari is highly recommended so it syncs iCloud tabs before quitting
      osascript -e 'quit app "Safari"' >/dev/null 2>&1 || pkill -x "Safari"

      local wait_count=0
      while pgrep -x "Safari" >/dev/null && ((wait_count < 10)); do
        sleep 0.5
        ((wait_count++))
      done
    else
      printf '[DRY-RUN] Would close app: Safari\n'
    fi
  fi

  # 2. Clear Safari Caches (Safe)
  safe_rm "${HOME}/Library/Caches/com.apple.Safari"
  safe_rm "${HOME}/Library/Containers/com.apple.Safari/Data/Library/Caches"

  # 3. Clear Cookies & Site Data (Destructive: Logs you out of websites)
  local data_targets=(
    "${HOME}/Library/Cookies/Cookies.binarycookies" # Global WebKit cookies
    "${HOME}/Library/Safari/LocalStorage"           # Site settings & offline data
    "${HOME}/Library/Safari/Databases"              # IndexedDB equivalents
    "${HOME}/Library/Safari/Service Workers"        # Background site workers
  )

  for target in "${data_targets[@]}"; do
    # Passing folders/files with a wildcard to ensure contents are purged
    if [[ -d "${target}" ]]; then
      safe_rm "${target}/"*
    elif [[ -f "${target}" ]]; then
      safe_rm "${target}"
    fi
  done

  # 4. Relaunch if it was running
  if ${was_killed}; then
    if ! ${DRY_RUN}; then
      sparkle "Relaunching Safari..."
      run_cmd open -a "Safari"
    else
      printf '[DRY-RUN] Would relaunch app: Safari\n'
    fi
  fi
}

clean_chrome_completely() {
  local chrome_base="${HOME}/Library/Application Support/Google/Chrome"

  if [[ ! -d "${chrome_base}" ]]; then
    return 0
  fi

  sparkle "Deep Cleaning Google Chrome (All Profiles)..."

  local was_killed=false

  # 1. Safely close Chrome and remember if we did
  if pgrep -xi "Google Chrome" >/dev/null; then
    was_killed=true
    if ! ${DRY_RUN}; then
      if ${VERBOSE}; then printf '[VERBOSE] Closing Google Chrome...\n'; fi
      pkill -xi "Google Chrome"

      local wait_count=0
      while pgrep -xi "Google Chrome" >/dev/null && ((wait_count < 10)); do
        sleep 0.5
        ((wait_count++))
      done
    else
      printf '[DRY-RUN] Would close app: Google Chrome\n'
    fi
  fi

  # 2. Clear Global App Caches
  safe_rm "${HOME}/Library/Caches/Google/Chrome"
  safe_rm "${chrome_base}/Crashpad"

  # 3. Find and iterate through all profiles
  if require_cmd fd; then
    mapfile -t chrome_profiles < <(fd -t d -d 1 '^(Default|Profile .*)$' "${chrome_base}" || true)
  else
    mapfile -t chrome_profiles < <(find "${chrome_base}" -maxdepth 1 -type d \( -name "Default" -o -name "Profile *" \) || true)
  fi

  for profile_dir in "${chrome_profiles[@]}"; do
    [[ -z "${profile_dir}" ]] && continue

    local profile_name
    profile_name="$(basename "${profile_dir}")"

    if ${VERBOSE}; then
      printf '[VERBOSE] Purging data for Chrome profile: %s\n' "${profile_name}"
    fi

    # --- CACHE TARGETS ---
    local cache_targets=("Cache" "Code Cache" "GPUCache" "DawnCache" "Service Worker/CacheStorage" "Service Worker/ScriptCache")
    for sub in "${cache_targets[@]}"; do
      safe_rm "${profile_dir}/${sub}"
    done

    # --- COOKIES & HISTORY TARGETS ---
    local data_targets=(
      "Network/Cookies"
      "Network/Cookies-journal"
      "History"
      "History-journal"
      "History Provider Cache"
      "Top Sites"
      "Top Sites-journal"
      "Visited Links"
      "Local Storage"   # <-- Modern site settings & offline data
      "IndexedDB"       # <-- Web app databases (Notion, Figma, etc.)
      "Session Storage" # <-- Active session data
    )
    for sub in "${data_targets[@]}"; do
      safe_rm "${profile_dir}/${sub}"
    done
  done

  # 4. Relaunch if it was running
  if ${was_killed}; then
    if ! ${DRY_RUN}; then
      sparkle "Relaunching Google Chrome..."
      run_cmd open -a "Google Chrome"
    else
      printf '[DRY-RUN] Would relaunch app: Google Chrome\n'
    fi
  fi
}

# -----------------------------
# Disk space baseline
# -----------------------------
kib_free_before="$(df -kP / | awk 'NR==2{print $4}')"
bytes_free_before=$((kib_free_before * 1024))

# -----------------------------
# macOS & Local Updates
# -----------------------------
if require_cmd softwareupdate; then
  sparkle "Checking macOS updates..."
  # Kick the background daemon to prep future updates
  run_cmd --show --bg sudo softwareupdate --background --force

  # Capture the update list (redirecting stderr to stdout to catch all output)
  su_output=$(sudo softwareupdate --list --all 2>&1 || true)

  # Print the captured output if running in verbose mode
  if ${VERBOSE}; then
    printf '[VERBOSE] %s\n' "${su_output}"
  fi

  # Check if the specific string exists in the output
  if grep -Fq "No new software available" <<<"${su_output}"; then
    sparkle "macOS is already up to date."
  else
    # Updates are available! Check the flag before installing.
    if ${DO_UPDATES}; then
      sparkle "Installing macOS updates..."
      # Using --show so you can see the Apple progress bar during installation
      run_cmd --show sudo softwareupdate --install --all --agree-to-license
    else
      sparkle "macOS updates are available:"
      printf '%s\n' "${su_output}"
      sparkle "DO_UPDATES is false. Skipping install..."
    fi
  fi
fi

HYPERION_SCRIPT="./update_hyperion.sh"
if [[ -x ${HYPERION_SCRIPT} ]]; then
  sparkle "Upgrading Hyperion..."
  "${HYPERION_SCRIPT}" --quiet || true
fi

# -----------------------------
# Package Managers
# -----------------------------
if require_cmd brew; then
  sparkle "Updating Homebrew..."
  run_cmd brew update

  sparkle "Upgrading formulae..."
  if ((${#EXCLUDE_FORMULAE[@]} == 0)); then
    run_cmd --show brew upgrade --formula || true
  else
    # Collect outdated formulae
    OUTDATED_FORMULAE=()
    while IFS= read -r line; do
      [[ -n ${line} ]] && OUTDATED_FORMULAE+=("${line}")
    done < <(brew outdated --formula --greedy --quiet || true)

    UPGRADE_FORMULAE=()
    for pkg in "${OUTDATED_FORMULAE[@]}"; do
      if [[ " ${EXCLUDE_FORMULAE[*]-} " != *" ${pkg} "* ]]; then
        UPGRADE_FORMULAE+=("${pkg}")
      fi
    done

    if ((${#UPGRADE_FORMULAE[@]} > 0)); then
      sparkle "Upgrading: ${UPGRADE_FORMULAE[*]}"
      # brew upgrade --no-quarantine --formula "${UPGRADE_FORMULAE[@]}" || true
      run_cmd --show brew upgrade --formula "${UPGRADE_FORMULAE[@]}" || true
    else
      sparkle "No formulae to upgrade"
    fi
  fi

  # Casks
  sparkle "Upgrading Homebrew casks..."
  if ((${#EXCLUDE_CASKS[@]} == 0)); then
    run_cmd --show brew upgrade --greedy --cask || true
  else
    OUTDATED_CASKS=()
    while IFS= read -r line; do
      [[ -n ${line} ]] && OUTDATED_CASKS+=("${line}")
    done < <(brew outdated --cask --greedy --quiet || true)

    UPGRADE_CASKS=()
    for pkg in "${OUTDATED_CASKS[@]}"; do
      if [[ " ${EXCLUDE_CASKS[*]-} " != *" ${pkg} "* ]]; then
        UPGRADE_CASKS+=("${pkg}")
      fi
    done

    if ((${#UPGRADE_CASKS[@]} > 0)); then
      sparkle "Upgrading: ${UPGRADE_CASKS[*]}"
      # brew upgrade --no-quarantine --greedy --cask "${UPGRADE_CASKS[@]}" || true
      run_cmd --show brew upgrade --greedy --cask "${UPGRADE_CASKS[@]}" || true
    else
      sparkle "No casks to upgrade"
    fi
  fi

  sparkle "Cleaning Homebrew cache..."
  run_cmd --show brew tap --repair
  run_cmd --show brew doctor
  run_cmd brew cleanup --scrub --prune=all

  bcache="$(brew --cache 2>/dev/null || true)"
  if [[ -n "${bcache}" ]]; then
    safe_rm "${bcache}"
  fi

  sparkle "Done brewing..."
fi

if require_cmd zsh && zsh -i -c 'command -v zimfw >/dev/null' >/dev/null 2>&1; then
  sparkle "Upgrading Zim & Modules..."
  if ${DRY_RUN}; then
    printf '[DRY-RUN] Would update zimfw\n'
  else
    zsh -i -c "zimfw upgrade" | grep -v "Already up to date" || true
    zsh -i -c "zimfw update" | grep -v "Already up to date" || true
  fi
fi

if require_cmd tlmgr; then
  sparkle "Updating TeX Live packages..."
  if [[ -d /usr/local/texlive ]]; then
    run_cmd sudo chown -R "$(id -un):$(id -g)" /usr/local/texlive
  fi
  run_cmd --show sudo tlmgr update --self --all --reinstall-forcibly-removed
fi

# -----------------------------
# Mamba/conda
# -----------------------------
if require_cmd mamba; then
  sparkle "Updating base mamba environment..."
  mamba update -n base -yq --all >/dev/null 2>&1 || true

  if ${UPDATE_MAMBA_ENVS}; then
    if require_cmd jq; then
      # Collect env names under .../envs/*
      mapfile -t MAMBA_ENVS < <(mamba env list --json | jq -r '.envs[] | select(test("/envs/")) | split("/")[-1]' || true)
    else
      # Fallback without jq
      MAMBA_ENVS=()
      while IFS= read -r p; do
        [[ -n ${p} ]] && MAMBA_ENVS+=("$(basename "${p}")")
      done < <(mamba env list 2>/dev/null | awk '/\/envs\//{print $NF}' || true)
    fi

    if ((${#MAMBA_ENVS[@]} > 0)); then
      echo "Found ${#MAMBA_ENVS[@]} environments: ${MAMBA_ENVS[*]}"
    fi

    for env in "${MAMBA_ENVS[@]:-}"; do
      for skip in "${MAMBA_SKIP_ENVS[@]}"; do
        [[ ${env} == "${skip}" ]] && continue 2
      done
      sparkle "Updating mamba env: ${env}"
      # mamba update -n "${env}" -yq --all > /dev/null 2>&1 || true
      mamba update -n "${env}" -y --all || true # > /dev/null 2>&1 || true
    done
  fi

  sparkle "Cleaning mamba caches..."
  mamba clean -yq --all >/dev/null 2>&1 || true
fi

if require_cmd npm; then
  sparkle "Updating global npm packages & clearing cache..."
  run_cmd npm install -g npm@latest
  run_cmd --show npm update -g
  run_cmd npm cache clean --force
fi

if require_cmd gem; then
  sparkle "Updating Ruby gems..."
  run_cmd --show gem update
  sparkle "Updated Ruby gems..."
fi

if require_cmd uv; then
  sparkle "Updating uv tools & python..."
  run_cmd --show uv tool upgrade --all --pre
  run_cmd --show uv python upgrade
  sparkle "Pruning uv cache..."
  run_cmd --show uv cache prune
fi

# Language Caches
sparkle "Cleaning language package caches..."
if require_cmd python3; then run_cmd --show python3 -m pip cache purge; fi
if require_cmd cargo; then run_cmd --show cargo cache -a; fi
if require_cmd go; then run_cmd --show go clean -modcache; fi
if require_cmd gem; then run_cmd --show gem cleanup; fi

# -----------------------------
# Deep System Purge
# -----------------------------
sparkle "Emptying Trash..."
safe_rm "${HOME}/.Trash/"*

sparkle "Clearing system and user log files..."
safe_sudo_rm /var/log/*
safe_sudo_rm /Library/Logs/*
safe_rm "${HOME}/Library/Logs/"*

sparkle "Clearing QuickLook and Font caches..."
run_cmd qlmanage -r cache
run_cmd atsutil databases -remove

sparkle "Thinning Time Machine local snapshots..."
run_cmd sudo tmutil thinlocalsnapshots / 10000000000 4

# -----------------------------
# Developer Tool Cleanup
# -----------------------------
if require_cmd docker && docker info >/dev/null 2>&1; then
  sparkle "Docker is running. Pruning system & volumes..."
  run_cmd docker system prune -f
  run_cmd docker builder prune -f
  run_cmd docker volume prune -f
fi

sparkle "Clearing Xcode Derived Data & Archives..."
safe_rm "${HOME}/Library/Developer/Xcode/DerivedData/"*
safe_rm "${HOME}/Library/Developer/Xcode/Archives/"*
safe_rm "${HOME}/Library/Developer/CoreSimulator/Caches/"*

if ${CLEAR_CHROME}; then
  clean_chrome_completely
  clean_safari_completely
else
  sparkle "Skipping Google Chrome clearing..."
fi

clean_electron_app() {
  local base_path="$1"
  local app_name="$2"

  sparkle "Cleaning caches for: ${app_name}..."

  local was_killed=false
  local app_bundle=""

  # 1. Safely close app and capture its path
  if pgrep -xi "${app_name}" >/dev/null; then
    was_killed=true

    # Smart trick: Grab the actual .app path before killing it.
    # This fixes apps like "Code" that are actually "Visual Studio Code.app"
    local pid
    pid=$(pgrep -xi "${app_name}" | head -n 1 || true)
    if [[ -n "${pid}" ]]; then
      local exec_path
      exec_path=$(ps -p "${pid}" -o comm= || true)
      # Extract everything up to the ".app/" directory
      if [[ "${exec_path}" == *".app/"* ]]; then
        app_bundle="${exec_path%%.app/*}.app"
      fi
    fi

    if ! ${DRY_RUN}; then
      if ${VERBOSE}; then printf '[VERBOSE] Closing %s...\n' "${app_name}"; fi
      pkill -xi "${app_name}"

      local wait_count=0
      while pgrep -xi "${app_name}" >/dev/null && ((wait_count < 10)); do
        sleep 0.5
        ((wait_count++))
      done
      sparkle "Killed %s..." "${app_name}"
    else
      printf '[DRY-RUN] Would close app: %s\n' "${app_name}"
    fi
  fi

  # 2. Main Caches
  local targets=("Cache" "Code Cache" "GPUCache" "DawnCache" "Service Worker/CacheStorage" "Service Worker/ScriptCache")
  for sub in "${targets[@]}"; do
    if [[ -d "${base_path}/${sub}" ]]; then
      safe_rm "${base_path}/${sub}"
    fi
  done

  # 3. Partitions
  if [[ -d "${base_path}/Partitions" ]]; then
    for partition in "${base_path}/Partitions"/*; do
      if [[ -d "${partition}" ]]; then
        for sub in "${targets[@]}"; do
          if [[ -d "${partition}/${sub}" ]]; then
            safe_rm "${partition}/${sub}"
          fi
        done
      fi
    done
  fi

  # 4. Relaunch if it was running
  if ${was_killed}; then
    if ! ${DRY_RUN}; then
      sparkle "Relaunching ${app_name}..."
      # Use the captured bundle path if we found it, otherwise fallback to the app name
      if [[ -n "${app_bundle}" && -e "${app_bundle}" ]]; then
        run_cmd open "${app_bundle}"
      else
        run_cmd open -a "${app_name}" || true
      fi
    else
      printf '[DRY-RUN] Would relaunch app: %s\n' "${app_name}"
    fi
  fi
}

sparkle "Dynamically discovering Electron & Chromium app caches..."

# Find all directories in Application Support (up to 3 levels deep) that contain a "GPUCache" folder.
# We then strip the "/GPUCache" off the end of the path to get the app's root directory.
# mapfile -t electron_apps < <(find "${HOME}/Library/Application Support" -maxdepth 3 -type d -name "GPUCache" -prune | awk -F'/GPUCache' '{print $1}' || true)
# Find all directories in Application Support (up to 3 levels deep) named "GPUCache".
# We use '-x dirname' to execute dirname on each result, stripping '/GPUCache' from the path.
if require_cmd fd; then
  mapfile -t electron_apps < <(fd -t d -g "GPUCache" -d 3 "${HOME}/Library/Application Support" -x dirname || true)
else
  # Fallback to find if fd is not installed
  mapfile -t electron_apps < <(find "${HOME}/Library/Application Support" -maxdepth 3 -type d -name "GPUCache" -prune | awk -F'/GPUCache' '{print $1}' || true)
fi

if ((${#electron_apps[@]} > 0)); then
  # Deduplicate the list just in case
  mapfile -t unique_apps < <(printf "%s\n" "${electron_apps[@]}" | sort -u)

  # 1. Collect all the parsed app names into a new array
  app_names=()
  for app_path in "${unique_apps[@]}"; do
    app_name="$(basename "${app_path}")"

    # Chromium profile edge-case
    if [[ "${app_name}" == "Default" ]]; then
      app_name="$(basename "$(dirname "${app_path}")")"
    fi

    app_names+=("${app_name}")
  done

  # 2. Print the list of cleaned names
  sparkle "Discovered apps: ${app_names[*]}"

  # 3. Loop through the array indices to run the cleanup
  for i in "${!unique_apps[@]}"; do
    clean_electron_app "${unique_apps[$i]}" "${app_names[$i]}"
  done
else
  sparkle "No dynamic Electron apps found."
fi

if ${CLEAR_IOS}; then
  sparkle "Clearing iOS/iPadOS Local Backups..."
  safe_rm "${HOME}/Library/Application Support/MobileSync/Backup/"*
fi

# -----------------------------
# System Resets
# -----------------------------
sparkle "Cleaning DNS cache..."
run_cmd dscacheutil -flushcache
run_cmd sudo killall -HUP mDNSResponder

if ${CLEAR_LAUNCHPAD}; then
  sparkle "Clearing Launchpad..."
  run_cmd defaults write com.apple.dock ResetLaunchPad -bool true
  run_cmd killall Dock
fi

# -----------------------------
# Wrap Up
# -----------------------------
if ${DRY_RUN}; then
  sparkle "Dry-run complete. No files were actually deleted."
else
  sparkle "Cleanup Success!"

  kib_free_after="$(df -kP / | awk 'NR==2{print $4}')"
  bytes_free_after=$((kib_free_after * 1024))
  delta=$((bytes_free_after - bytes_free_before))

  bytes_to_human "${delta}"
  if ${LOG_OUTPUT}; then
    printf "\nDetailed log saved to: %s\n" "${LOG_FILE}"
  fi
fi
