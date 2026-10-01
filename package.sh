# maid.sh is build output (not in git). In a local checkout that has been
# built (`just link`) expose it as bin/maid, so no download happens.
# Otherwise (a plain `basher install`) fetch the latest GitHub release whenever
# basher sources this file (install and upgrade). That needs `gh` auth while the
# repo is private; the old binary is kept on failure.
BINS=bin/maid

if [ -f "${BASH_SOURCE[0]%/*}/maid.sh" ]; then
  mkdir -p "${BASH_SOURCE[0]%/*}/bin" &&
    ln -sf ../maid.sh "${BASH_SOURCE[0]%/*}/bin/maid"
else
  (
    dir="${BASH_SOURCE[0]%/*}/bin"
    mkdir -p "$dir" &&
      env -u GH_TOKEN -u GITHUB_TOKEN gh release download \
        --repo claudiosv/macos_maid --pattern maid.sh --output "$dir/maid.new" --clobber &&
      chmod +x "$dir/maid.new" &&
      mv "$dir/maid.new" "$dir/maid"
  ) || echo "maid: could not download the latest release (gh auth login?)" >&2
fi
