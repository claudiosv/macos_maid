# Stages: shell tooling and language package managers.

stage_shell_tools() {
  # Quarantine flags on Codex/ChatGPT's computer-use helper block it from launching
  local codex="${HOME}/.config/codex/computer-use/Codex Computer Use.app"
  local chatgpt="/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/sky/Codex Computer Use.app"
  if [[ -e "$codex" || -e "$chatgpt" ]]; then
    step "Dequarantining Codex..."
    if [[ -e "$codex" ]]; then
      run_cmd --show xattr -dr com.apple.quarantine "$codex"
    fi
    if [[ -e "$chatgpt" ]]; then
      run_cmd --show sudo xattr -dr com.apple.quarantine "$chatgpt"
    fi
  fi

  if require_cmd zsh && zsh -i -c 'command -v zimfw >/dev/null' >/dev/null 2>&1; then
    step "Upgrading Zim & Modules..."
    if "$DRY_RUN"; then
      dry "Would update zimfw"
    else
      zsh -i -c "zimfw upgrade" | grep -v "Already up to date" || true
      zsh -i -c "zimfw update" | grep -v "Already up to date" || true
    fi
  fi
}

stage_tex() {
  require_cmd tlmgr || return 0
  step "Updating TeX Live packages..."

  if [[ -d /usr/local/texlive ]]; then
    run_cmd sudo chown -R "$(whoami):admin" /usr/local/texlive
  fi
  run_cmd --show tlmgr update --self --all --reinstall-forcibly-removed
  run_cmd --show tlmgr update --all
  run_cmd --show tlmgr --usermode update --all
  run_cmd texhash
  run_cmd texhash ~/Library/texmf
}

stage_mamba() {
  require_cmd mamba || return 0
  step "Updating base mamba environment..."
  mamba update -n base -yq --all >/dev/null 2>&1 || true

  if "$UPDATE_MAMBA_ENVS"; then
    local -a envs=()
    local p env skip
    if require_cmd jq; then
      # Env names under .../envs/*
      mapfile -t envs < <(mamba env list --json | jq -r '.envs[] | select(test("/envs/")) | split("/")[-1]' || true)
    else
      while IFS= read -r p; do
        [[ -n ${p} ]] && envs+=("$(basename "$p")")
      done < <(mamba env list 2>/dev/null | awk '/\/envs\//{print $NF}' || true)
    fi

    if ((${#envs[@]} > 0)); then
      step "Found %d environments: %s" "${#envs[@]}" "${envs[*]}"
    fi

    for env in "${envs[@]:-}"; do
      for skip in "${MAMBA_SKIP_ENVS[@]:-}"; do
        [[ -n ${skip} && ${env} == "$skip" ]] && continue 2
      done
      step "Updating mamba env: %s" "$env"
      mamba update -n "$env" -y --all || true
    done
  fi

  step "Cleaning mamba caches..."
  mamba clean -yq --all >/dev/null 2>&1 || true
}

stage_language_packages() {
  if require_cmd pnpm; then
    step "Updating global pnpm packages & clearing cache..."
    run_cmd pnpm self-update
    run_cmd --show pnpm update -g
    run_cmd pnpm store prune
  fi

  if require_cmd rustup; then
    step "Updating Rust toolchains..."
    run_cmd --show rustup update
  fi

  # cargo-update is a third-party subcommand: `cargo install cargo-update`
  if require_cmd cargo-install-update; then
    step "Updating cargo-installed binaries..."
    run_cmd --show cargo install-update -a
  fi

  if require_cmd gem; then
    step "Updating Ruby gems..."
    run_cmd --show gem update
  fi

  if require_cmd uv; then
    step "Updating uv tools & python..."
    run_cmd --show uv tool upgrade --all --pre
    run_cmd --show uv python upgrade
  fi

  step "Cleaning language package caches..."
  if require_cmd python3; then run_cmd --show python3 -m pip cache purge; fi
  # cargo-cache is a third-party subcommand: `cargo install cargo-cache`
  if require_cmd cargo-cache; then run_cmd --show cargo cache -a; fi
  if require_cmd go; then run_cmd --show go clean -modcache; fi
  if require_cmd gem; then run_cmd --show gem cleanup; fi
}
