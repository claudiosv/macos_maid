# maid

A single-command macOS cleanup and update utility: it updates macOS, Homebrew and language tooling, empties caches and logs, and resets a few system services.

maid is a plain bash script. It is built with [bashly](https://bashly.dev) into a single file (`maid.sh`) and uses a vendored copy of [clack.sh](src/lib/UPSTREAM.md) for the output. It runs on macOS only and asks for `sudo` once at the start, then keeps the credentials alive until it finishes.

## Install

### With basher

[basher](https://github.com/basherpm/basher) is a package manager for shell scripts.

```sh
basher install claudiosv/macos_maid
maid --help
```

`maid.sh` is build output and is not committed to git. Instead, basher sources the repo's `package.sh`, which downloads the latest `maid.sh` from the GitHub release into `bin/maid`. This has two consequences:

- **`gh` is required** and must be authenticated (`gh auth login`) while the repository is private. If the download fails, maid prints `could not download the latest release (gh auth login?)` and keeps the previously installed binary.
- **Upgrading:** `basher upgrade claudiosv/macos_maid` re-runs `package.sh`, which downloads the latest release every time.

When installed through basher the command is `maid`; elsewhere in this README it is written `maid.sh`.

### From a release

```sh
gh release download --repo claudiosv/macos_maid --pattern 'maid.sh*' --dir /tmp/maid
(cd /tmp/maid && shasum -a 256 -c maid.sh.sha256)
install -m 755 /tmp/maid/maid.sh ~/.local/bin/maid
```

### From source

```sh
git clone git@github.com:claudiosv/macos_maid.git && cd macos_maid
just build        # runs `bashly generate`, writes ./maid.sh
./maid.sh --help
```

`just install` builds and installs to `~/.local/bin/maid` (override with `PREFIX`). `just link` registers the checkout with basher without downloading anything.

## Requirements

macOS, bash 4.2 or newer (the stock `/bin/bash` is too old, so install a newer one with Homebrew), and an admin account. Everything else is optional: each stage is skipped when its tool is not installed.

| Tool | Stage |
|------|-------|
| `brew` | Homebrew update, upgrade and cleanup |
| `tlmgr` | TeX Live updates |
| `mamba` | base environment update, `--mamba` for the rest |
| `pnpm`, `gem`, `uv`, `python3`, `go` | language package updates and cache cleaning |
| `rustup` | Rust toolchain update |
| `cargo-install-update` ([cargo-update](https://crates.io/crates/cargo-update)) | update of `cargo install`ed binaries |
| `cargo-cache` | cargo cache cleaning |
| `docker`, `podman` | prune, only when the daemon or machine is running |
| `zsh` with `zimfw` | Zim upgrade |
| `fd`, `jq` | used when present, with `find` and `awk` fallbacks |

## Usage

```sh
maid.sh [OPTIONS]
```

```sh
maid.sh --dry-run --verbose     # preview everything
maid.sh --chrome --electron     # also clear browser and app data
```

Run `maid.sh --dry-run --verbose` first. Dry-run prints what would be executed or removed and changes nothing, although `sudo` is still requested up front.

### Options

| Flag | Description |
|------|-------------|
| `--no-updates`, `-u` | Do not install macOS updates. Available updates are still listed |
| `--launchpad`, `-l` | Clear the Launchpad layout. This is already the default |
| `--chrome`, `-c` | Clear Chrome and Safari history, cookies and site data |
| `--electron`, `-e` | Clear caches of Electron/Chromium apps |
| `--ios`, `-i` | Delete iOS/iPadOS local backups |
| `--mamba`, `-m` | Update every Mamba environment, not just `base` |
| `--dry-run`, `-n` | Show what would be done without doing it |
| `--verbose`, `-v` | Print executed commands and removed paths |
| `--log`, `-o` | Also write the output to `~/Library/Logs/MacCleanup/cleanup_<timestamp>.log` |

## What it does

Stages run in this order:

1. **macOS updates:** triggers the background update daemon, lists updates and installs them unless `--no-updates`.
2. **Homebrew:** `brew update`, upgrades formulae and casks (greedy), `brew tap --repair`, `brew doctor`, `brew cleanup --scrub --prune=all`, then removes the download cache. Packages in `EXCLUDE_FORMULAE` / `EXCLUDE_CASKS` are skipped.
3. **Shell tools:** removes the quarantine flag from Codex's computer-use helper and upgrades Zim.
4. **TeX Live:** `tlmgr update` for the system and user trees, then `texhash`.
5. **Mamba:** updates `base`, optionally all environments (`--mamba`, minus `MAMBA_SKIP_ENVS`), then cleans its caches.
6. **Language packages:** updates pnpm, Rust toolchains, cargo binaries, gems, uv tools and Python, then purges the pip, cargo, Go module and gem caches.
7. **Purge:** empties the Trash, clears system and user logs, QuickLook and font caches, and thins Time Machine local snapshots.
8. **Dev cleanup:** prunes Docker and Podman and clears Xcode DerivedData, Archives and simulator caches.
9. **Browsers:** with `--chrome`, clears Chrome (all profiles) and Safari. With `--electron`, clears caches of every Electron/Chromium app found in Application Support. Running apps are quit first and relaunched afterwards.
10. **iOS:** with `--ios`, deletes local device backups.
11. **Resets:** flushes the DNS cache and resets Launchpad.

It ends by reporting how much disk space was freed.

## Safety

- **Destructive by design:** `--chrome` logs you out of websites and erases browsing history, and `--ios` deletes device backups for good. Neither runs unless asked for.
- **Not removed:** passwords, bookmarks and extensions in Chrome and Safari. Electron apps only lose caches, not their data.
- **Dry-run first:** `--dry-run` routes every deletion and command through a wrapper that only prints.
- **Failures are not fatal:** a failing step does not stop the run. Use `--verbose` or `--log` to see what happened.
- **Local settings:** the excluded packages and skipped Mamba environments are variables at the top of `src/root_command.sh`; rebuild after changing them.

## Development

Needs [bashly](https://bashly.dev), [just](https://just.systems), `shfmt`, `shellharden`, `shellcheck`, [bats](https://github.com/bats-core/bats-core) and [rumdl](https://github.com/rvben/rumdl). `just dev-tools` installs them with Homebrew.

```sh
just build     # bashly generate -> maid.sh
just run -n -v # build, then run with the given flags
just fmt       # shfmt, rumdl and yamlfix
just harden    # shellharden --replace
just fix       # apply shellcheck's auto-fixes (diff format)
just lint      # build, then shfmt -d, shellharden --check, shellcheck, rumdl, yamlfix --check
just test      # build, then bats tests
just check     # lint + test
just hooks     # install the git hooks with prek
```

Layout:

```text
src/bashly.yml          flag definitions and version
src/root_command.sh     defaults, flag handling and the order of stages
src/initialize.sh       macOS check and bash options
src/lib/stage_*.sh      the stages (updates, packages, cleanup)
src/lib/apps.sh         quitting, relaunching and cleaning browsers and Electron apps
src/lib/exec.sh         run_cmd, safe_rm and safe_sudo_rm, which honor --dry-run and --verbose
src/lib/ui.sh           sudo keep-alive, logging, disk accounting
src/lib/clack.sh        vendored clack.sh (see UPSTREAM.md)
tests/maid.bats         bats tests
package.sh              basher install hook
```

### Releases

Releases are explicit; nothing is published on a plain push. CI (`.github/workflows/ci.yml`) runs on every push and pull request.

```sh
just bump minor     # set the version in src/bashly.yml, commit
just tag            # push the branch and a signed v<version> tag
just release patch  # check, bump and tag in one go
```

A `v*` tag triggers `release.yml`, which re-runs CI, builds `maid.sh` and publishes it with `maid.sh.sha256`.

## License

No license has been specified yet.
