#!/usr/bin/env bats

# Every command that could touch the machine is a logging stub, so runs are safe.
setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STUB="$BATS_TEST_TMPDIR/bin"
  CALLS="$STUB/calls"
  mkdir -p "$STUB" "$BATS_TEST_TMPDIR/home"
  ln -s "$BASH" "$STUB/bash"
  for c in sudo softwareupdate brew killall defaults qlmanage atsutil tmutil \
    dscacheutil rm zsh osascript gem pnpm uv python3 go docker podman rustup cargo cargo-install-update mamba tlmgr sleep; do
    cat >"$STUB/$c" <<'STUB_EOF'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >>"$(dirname "$0")/calls"
if [[ "$(basename "$0") $*" == *"--list"* ]]; then echo "${STUB_SU_OUT-}"; fi
STUB_EOF
    chmod +x "$STUB/$c"
  done
  printf '#!/usr/bin/env bash\necho Darwin\n' >"$STUB/uname"
  chmod +x "$STUB/uname"
  : >"$CALLS"
  export HOME="$BATS_TEST_TMPDIR/home" PATH="$STUB:/usr/bin:/bin"
  export STUB_SU_OUT="Software Update Tool

Software Update found the following new or updated software:
* Label: macOS 99"
}

# 3>&- so backgrounded children (sudo keep-alive) do not hold bats open
maid() { bash "$ROOT/maid.sh" "$@" 3>&-; }

@test "--help and --version exit 0" {
  run maid --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dry-run"* ]]
  run maid --version
  [ "$status" -eq 0 ]
}

@test "--dry-run removes nothing and installs nothing" {
  run maid --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry-run complete"* ]]
  ! grep -q '^rm ' "$CALLS"
  ! grep -q -e '--install' "$CALLS"
}

@test "updates install by default" {
  run maid
  [ "$status" -eq 0 ]
  grep -q -e 'softwareupdate --install' "$CALLS"
}

@test "--no-updates skips the install" {
  run maid --no-updates
  [ "$status" -eq 0 ]
  ! grep -q -e '--install' "$CALLS"
}

@test "stages run in a normal run" {
  run maid
  [ "$status" -eq 0 ]
  grep -q '^rm ' "$CALLS"
  grep -q '^dscacheutil -flushcache' "$CALLS"
}

@test "docker and podman are pruned when running" {
  run maid
  [ "$status" -eq 0 ]
  grep -q '^docker system prune -f' "$CALLS"
  grep -q '^podman system prune -f' "$CALLS"
  grep -q '^podman volume prune -f' "$CALLS"
}

@test "rust toolchains and cargo binaries are updated" {
  run maid
  [ "$status" -eq 0 ]
  grep -q '^rustup update' "$CALLS"
  grep -q '^cargo install-update -a' "$CALLS"
}
