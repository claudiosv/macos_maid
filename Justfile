# Default recipe: generate the script
default: generate

# Compile the bashly.yml and src/ files into the final maid.sh script
generate:
    bashly generate
    chmod +x maid.sh

# Run the generated script (e.g., `just run --dry-run` or `just run -v`)
run +args="": generate
    ./maid.sh {{args}}

# Quick command to run the script in dry-run mode
dry-run: generate
    ./maid.sh --dry-run

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