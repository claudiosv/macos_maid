# Our own shell sources; vendored clack.sh and the generated maid.sh are excluded.
srcs := `fd -e sh . src --exclude clack.sh | sort | tr '\n' ' '`

default: build

# Install the dev toolchain (macOS).
dev-tools:
    brew install uv shellcheck shfmt bats-core rumdl just prek fd ruby
    gem install bashly
    cargo binstall --no-confirm shellharden || cargo install shellharden
    uv tool install yamllint
    uv tool install yamlfix

# Build the single-file CLI from src/ with bashly.
build:
    bashly generate
    chmod +x maid.sh

# Run the freshly built script (e.g. `just run --dry-run -v`).
run +args="": build
    ./maid.sh {{args}}

dry-run +args="": build
    ./maid.sh --dry-run --verbose {{args}}

fmt:
    shfmt -w {{srcs}}
    rumdl fmt .
    uvx yamlfix settings.yml src/bashly.yml

# Apply shellcheck's auto-fixes (only fixable findings produce a diff).
fix:
    shellcheck -s bash -f diff {{srcs}} | git apply --allow-empty

harden:
    shellharden --replace {{srcs}}

# Build from the local checkout and install it (no download). PREFIX defaults to ~/.local.
install prefix=env("PREFIX", home_directory() / ".local"): build
    install -d {{prefix}}/bin
    install -m 755 maid.sh {{prefix}}/bin/maid
    @echo "installed {{prefix}}/bin/maid"

# Build and register this checkout with basher (symlinks ./maid.sh as `maid`; no download).
# If basher already has claudiosv/macos_maid installed: basher uninstall claudiosv/macos_maid
link: build
    basher link . claudiosv/macos_maid

# Read-only checks (same as the pre-commit hooks).
lint: build
    shfmt -d {{srcs}}
    shellharden --check {{srcs}}
    shellcheck -S warning -e SC2034,SC2206 maid.sh
    rumdl check .
    uvx yamlfix --check settings.yml src/bashly.yml

test: build
    bats tests

check: lint test

hooks:
    prek install

# Regenerate README.md from bashly.yml.
docs:
    bashly render :markdown_github .
    rumdl fmt .

# --- Releases are explicit: nothing is published unless you run bump/tag/release. ---

# Set the version in src/bashly.yml (major|minor|patch|X.Y.Z), refresh docs, commit.
bump part="patch":
    #!/usr/bin/env bash
    set -euo pipefail
    cur="$(gsed -n 's/^version: *//p' src/bashly.yml | head -n1)"
    IFS=. read -r ma mi pa <<<"$cur"
    case "{{part}}" in
      major) new="$((ma + 1)).0.0" ;;
      minor) new="${ma}.$((mi + 1)).0" ;;
      patch) new="${ma}.${mi}.$((pa + 1))" ;;
      [0-9]*.[0-9]*.[0-9]*) new="{{part}}" ;;
      *) echo "usage: just bump major|minor|patch|X.Y.Z" >&2; exit 1 ;;
    esac
    gsed -i "s/^version: .*/version: ${new}/" src/bashly.yml
    just docs
    git add src/bashly.yml README.md
    git commit -s -m "Version v${new}"
    echo "bumped ${cur} -> ${new}"

# Tag the current version and push branch + tag; the tag push triggers release.yml.
tag:
    #!/usr/bin/env bash
    set -euo pipefail
    v="v$(gsed -n 's/^version: *//p' src/bashly.yml | head -n1)"
    git push origin HEAD
    git tag -s "$v" -m "Release $v"
    git push origin "$v"
    echo "pushed $v; GitHub Actions will build and publish the release"

# check, bump, tag in one go.
release part="patch": check (bump part) tag
