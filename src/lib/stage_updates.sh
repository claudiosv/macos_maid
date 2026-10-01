# Stages: macOS and Homebrew updates.

stage_macos_updates() {
  require_cmd softwareupdate || return 0
  step "Checking macOS updates..."
  # Kick the background daemon to prep future updates
  run_cmd --bg sudo softwareupdate --background --force

  local su_output
  su_output="$(sudo softwareupdate --list --all 2>&1 || true)"
  verbose "$su_output"

  if grep -Fq "No new software available" <<<"$su_output"; then
    step "macOS is already up to date."
  elif "$DO_UPDATES"; then
    step "Installing macOS updates..."
    # --show so you can see the Apple progress bar
    run_cmd --show sudo softwareupdate --install --all --agree-to-license
  else
    step "macOS updates are available:"
    printf '%s\n' "$su_output"
    step "DO_UPDATES is false. Skipping install..."
  fi
}

# upgrade_filtered kind(formula|cask) exclude...: upgrade outdated packages except the excluded ones.
upgrade_filtered() {
  local kind="$1"
  shift
  local -a exclude=("$@") outdated=() todo=() flags=()
  local pkg
  if [[ "$kind" == "cask" ]]; then flags=(--cask --greedy); else flags=(--formula); fi

  if ((${#exclude[@]} == 0)); then
    run_cmd --show brew upgrade "${flags[@]}" --no-ask || true
    return 0
  fi

  while IFS= read -r pkg; do
    [[ -n ${pkg} ]] && outdated+=("$pkg")
  done < <(brew outdated "${flags[@]}" --greedy --quiet || true)

  for pkg in "${outdated[@]}"; do
    if [[ " ${exclude[*]} " != *" ${pkg} "* ]]; then todo+=("$pkg"); fi
  done

  if ((${#todo[@]} > 0)); then
    step "Upgrading: %s" "${todo[*]}"
    run_cmd --show brew upgrade "${flags[@]}" --no-ask "${todo[@]}" || true
  else
    step "No %ss to upgrade" "$kind"
  fi
}

stage_brew() {
  require_cmd brew || return 0
  step "Updating Homebrew..."
  run_cmd brew update

  step "Upgrading formulae..."
  upgrade_filtered formula "${EXCLUDE_FORMULAE[@]}"

  step "Upgrading Homebrew casks..."
  upgrade_filtered cask "${EXCLUDE_CASKS[@]}"

  step "Cleaning Homebrew cache..."
  run_cmd --show brew tap --repair
  run_cmd --show brew doctor
  run_cmd brew cleanup --scrub --prune=all

  local bcache
  bcache="$(brew --cache 2>/dev/null || true)"
  if [[ -n "$bcache" ]]; then safe_rm "$bcache"; fi

  step "Done brewing..."
}
