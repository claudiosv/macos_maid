# maid.sh

macOS Maid - A Comprehensive Mac Cleanup Utility

| Attributes       | &nbsp;
|------------------|-------------
| Version:         | 1.0.0

## Usage

```bash
maid.sh [OPTIONS]
```

## Examples

```bash
maid.sh --dry-run --verbose
```

```bash
maid.sh --chrome --electron
```

## Options

### *--no-updates, -u*

Do not install macOS updates

#### *--launchpad, -l*

Clear Launchpad layout

#### *--chrome, -c*

Clear Chrome and Safari

#### *--electron, -e*

Clear caches of Electron/Chromium apps

#### *--ios, -i*

Clear iOS/iPadOS local backups

#### *--mamba, -m*

Update Mamba environments

#### *--dry-run, -n*

Dry-run (show what would be deleted without doing it)

#### *--verbose, -v*

Verbose output (prints executed commands and removed paths)

#### *--log, -o*

Log execution output
