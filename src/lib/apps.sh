# Quitting/relaunching apps and cleaning their data.

# quit_app name [graceful]: returns 0 if the app was running (and was quit, or would be in dry-run).
quit_app() {
  local name="$1" graceful="${2:-false}" wait_count=0
  pgrep -xi "$name" >/dev/null || return 1
  if "$DRY_RUN"; then
    dry "Would close app: ${name}"
    return 0
  fi
  verbose "Closing ${name}..."
  # osascript lets Safari sync iCloud tabs before quitting
  if "$graceful"; then
    osascript -e "quit app \"${name}\"" >/dev/null 2>&1 || pkill -xi "$name"
  else
    pkill -xi "$name"
  fi
  while pgrep -xi "$name" >/dev/null && ((wait_count < 10)); do
    sleep 0.5
    ((wait_count++))
  done
  return 0
}

# relaunch_app name [bundle]: open the .app bundle if given and present, else by name.
relaunch_app() {
  local name="$1" bundle="${2:-}"
  if "$DRY_RUN"; then
    dry "Would relaunch app: ${name}"
    return 0
  fi
  step "Relaunching %s..." "$name"
  if [[ -n "$bundle" && -e "$bundle" ]]; then
    run_cmd open "$bundle"
  else
    run_cmd open -a "$name" || true
  fi
}

clean_safari_completely() {
  step "Deep Cleaning Safari..."

  local was_killed=false
  if quit_app "Safari" true; then was_killed=true; fi

  # Caches (safe)
  safe_rm "${HOME}/Library/Caches/com.apple.Safari"
  safe_rm "${HOME}/Library/Containers/com.apple.Safari/Data/Library/Caches"

  # Cookies & site data (destructive: logs you out of websites)
  local data_targets=(
    "${HOME}/Library/Cookies/Cookies.binarycookies" # Global WebKit cookies
    "${HOME}/Library/Safari/LocalStorage"           # Site settings & offline data
    "${HOME}/Library/Safari/Databases"              # IndexedDB equivalents
    "${HOME}/Library/Safari/Service Workers"        # Background site workers
  )

  local target
  for target in "${data_targets[@]}"; do
    # Folders get a wildcard so contents are purged but the folder stays
    if [[ -d "$target" ]]; then
      safe_rm "${target}/"*
    elif [[ -f "$target" ]]; then
      safe_rm "$target"
    fi
  done

  if "$was_killed"; then relaunch_app "Safari"; fi
}

clean_chrome_completely() {
  local chrome_base="${HOME}/Library/Application Support/Google/Chrome"
  [[ -d "$chrome_base" ]] || return 0

  step "Deep Cleaning Google Chrome (All Profiles)..."

  local was_killed=false
  if quit_app "Google Chrome"; then was_killed=true; fi

  safe_rm "${HOME}/Library/Caches/Google/Chrome"
  safe_rm "${chrome_base}/Crashpad"

  local chrome_profiles
  if require_cmd fd; then
    mapfile -t chrome_profiles < <(fd -t d -d 1 '^(Default|Profile .*)$' "$chrome_base" || true)
  else
    mapfile -t chrome_profiles < <(find "$chrome_base" -maxdepth 1 -type d \( -name "Default" -o -name "Profile *" \) || true)
  fi

  local cache_targets=("Cache" "Code Cache" "GPUCache" "DawnCache" "Service Worker/CacheStorage" "Service Worker/ScriptCache")
  local data_targets=(
    "Network/Cookies"
    "Network/Cookies-journal"
    "History"
    "History-journal"
    "History Provider Cache"
    "Top Sites"
    "Top Sites-journal"
    "Visited Links"
    "Local Storage"   # Site settings & offline data
    "IndexedDB"       # Web app databases (Notion, Figma, etc.)
    "Session Storage" # Active session data
  )

  local profile_dir sub
  for profile_dir in "${chrome_profiles[@]}"; do
    [[ -z "$profile_dir" ]] && continue
    verbose "Purging data for Chrome profile: $(basename "$profile_dir")"
    for sub in "${cache_targets[@]}" "${data_targets[@]}"; do
      safe_rm "${profile_dir}/${sub}"
    done
  done

  if "$was_killed"; then relaunch_app "Google Chrome"; fi
}

# clean_electron_app base_path app_name
clean_electron_app() {
  local base_path="$1" app_name="$2"

  step "Cleaning caches for: %s..." "$app_name"

  local was_killed=false app_bundle="" pid exec_path

  # Grab the real .app path before quitting (e.g. "Code" is "Visual Studio Code.app")
  pid="$(pgrep -xi "$app_name" | head -n 1 || true)"
  if [[ -n "$pid" ]]; then
    exec_path="$(ps -p "$pid" -o comm= || true)"
    if [[ "$exec_path" == *".app/"* ]]; then
      app_bundle="${exec_path%%.app/*}.app"
    fi
  fi

  if quit_app "$app_name"; then
    was_killed=true
    if ! "$DRY_RUN"; then step "Killed %s..." "$app_name"; fi
  fi

  local targets=("Cache" "Code Cache" "GPUCache" "DawnCache" "Service Worker/CacheStorage" "Service Worker/ScriptCache")
  local sub partition
  for sub in "${targets[@]}"; do
    if [[ -d "${base_path}/${sub}" ]]; then safe_rm "${base_path}/${sub}"; fi
  done

  if [[ -d "${base_path}/Partitions" ]]; then
    for partition in "${base_path}/Partitions"/*; do
      [[ -d "$partition" ]] || continue
      for sub in "${targets[@]}"; do
        if [[ -d "${partition}/${sub}" ]]; then safe_rm "${partition}/${sub}"; fi
      done
    done
  fi

  if "$was_killed"; then relaunch_app "$app_name" "$app_bundle"; fi
}

# Clean every Electron/Chromium app in Application Support that has a GPUCache dir.
clean_electron_apps() {
  step "Dynamically discovering Electron & Chromium app caches..."

  local electron_apps
  if require_cmd fd; then
    mapfile -t electron_apps < <(fd -t d -g "GPUCache" -d 3 "${HOME}/Library/Application Support" -x dirname || true)
  else
    mapfile -t electron_apps < <(find "${HOME}/Library/Application Support" -maxdepth 3 -type d -name "GPUCache" -prune -exec dirname {} \; || true)
  fi

  if ((${#electron_apps[@]} == 0)); then
    step "No dynamic Electron apps found."
    return 0
  fi

  local unique_apps app_names=() app_path app_name i
  mapfile -t unique_apps < <(printf "%s\n" "${electron_apps[@]}" | sort -u)

  for app_path in "${unique_apps[@]}"; do
    app_name="$(basename "$app_path")"
    # Chromium profile edge-case
    if [[ "$app_name" == "Default" ]]; then
      app_name="$(basename "$(dirname "$app_path")")"
    fi
    app_names+=("$app_name")
  done

  step "Discovered apps: %s" "${app_names[*]}"

  for i in "${!unique_apps[@]}"; do
    clean_electron_app "${unique_apps[$i]}" "${app_names[$i]}"
  done
}
