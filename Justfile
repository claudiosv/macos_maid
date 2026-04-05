# Default recipe: generate the script
default: generate

# Install bashly, may require

# brew install bash-completion
bashly:
    gem install bashly
    bashly completions --install

# Compile the bashly.yml and src/ files into the final maid.sh script
generate:
    bashly generate
    shfmt --case-indent --indent 2 -l -w maid.sh
    chmod +x maid.sh

production:
    bashly generate --env production
    chmod +x maid.sh

# Run the generated script (e.g., `just run --dry-run` or `just run -v`)
run +args="": generate
    ./maid.sh {{ args }}

# Quick command to run the script in dry-run mode
dry-run +args="": generate
    ./maid.sh --dry-run --verbose {{ args }}

# Install the script to your local bin directory (requires sudo)
# install: generate
#     sudo cp maid.sh /usr/local/bin/mac-maid
#     sudo chmod +x /usr/local/bin/mac-maid
#     @echo "mac-maid successfully installed to /usr/local/bin"

# View the bashly configuration
view:
    cat bashly.yml

# Clean up the generated files
clean:
    rm -f maid.sh

# Format the source files using shfmt
fmt:
    @echo "Formatting source files..."
    shfmt --case-indent --indent 2 -l -w src/
    shfmt --case-indent --indent 2 -l -w maid.sh
    @echo "Formatting Markdown files..."
    rumdl fmt .
    @echo "Formatting YAML configuration..."
    uv tool run yamlfix settings.yml src/bashly.yml

# Lint the source files and the generated script using shellcheck
lint: generate
    @echo "Linting source files..."
    shellcheck src/*.sh
    @echo "Linting generated cleanup.sh..."
    shellcheck maid.sh
    @echo "Linting Markdown files..."
    rumdl check .
    @echo "Checking YAML formatting..."
    uv tool run yamlfix --check settings.yml src/bashly.yml
    @echo "Linting YAML configuration..."
    -yamllint settings.yml src/bashly.yml

# Run formatting, linting, and generation all at once
check: fmt lint
    @echo "All checks passed!"

dev-tools:
    brew install uv yamlfmt shellcheck rumdl shfmt bash-completion
    uv tool install yamllint
    uv tool install yamlfix

docs:
    bashly render :markdown_github .
    rumdl fmt .