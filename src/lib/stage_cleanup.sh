# Stages: system purge, dev tools, browsers, resets.

stage_purge() {
  step "Emptying Trash..."
  safe_rm "${HOME}/.Trash/"*

  step "Clearing system and user log files..."
  safe_sudo_rm /var/log/*
  safe_sudo_rm /Library/Logs/*
  safe_rm "${HOME}/Library/Logs/"*

  step "Clearing QuickLook and Font caches..."
  run_cmd qlmanage -r cache
  run_cmd atsutil databases -remove
  run_cmd atsutil databases -removeUser
  run_cmd killall fontd
  run_cmd killall fontworker

  step "Thinning Time Machine local snapshots..."
  run_cmd sudo tmutil thinlocalsnapshots / 10000000000 4
}

stage_dev_cleanup() {
  local engine
  for engine in docker podman; do
    if require_cmd "$engine" && "$engine" info >/dev/null 2>&1; then
      step "%s is running. Pruning system & volumes..." "$engine"
      run_cmd "$engine" system prune -f
      run_cmd "$engine" builder prune -f
      run_cmd "$engine" volume prune -f
    fi
  done

  step "Clearing Xcode Derived Data & Archives..."
  safe_rm "${HOME}/Library/Developer/Xcode/DerivedData/"*
  safe_rm "${HOME}/Library/Developer/Xcode/Archives/"*
  safe_rm "${HOME}/Library/Developer/CoreSimulator/Caches/"*
}

stage_browsers() {
  if "$CLEAR_CHROME"; then
    clean_chrome_completely
    clean_safari_completely
  else
    step "Skipping Google Chrome clearing..."
  fi
  if "$CLEAR_ELECTRON_APP_CACHES"; then clean_electron_apps; fi
}

stage_ios() {
  "$CLEAR_IOS" || return 0
  step "Clearing iOS/iPadOS Local Backups..."
  safe_rm "${HOME}/Library/Application Support/MobileSync/Backup/"*
}

stage_resets() {
  step "Cleaning DNS cache..."
  run_cmd dscacheutil -flushcache
  run_cmd sudo killall -HUP mDNSResponder

  if "$CLEAR_LAUNCHPAD"; then
    step "Clearing Launchpad..."
    run_cmd defaults write com.apple.dock ResetLaunchPad -bool true
    run_cmd killall Dock
  fi
}
