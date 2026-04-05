#!/usr/bin/env bash
if ((BASH_VERSINFO[0]<4||(BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2)));then
printf "bash version 4.2 or higher is required\n" >&2
exit 1
fi
root_command(){
inspect_args
if [[ ${ERR_EXIT-0} == "1" ]];then set -o errexit;fi
if [[ ${PIPE_FAIL-0} == "1" ]];then set -o pipefail;fi
if [[ ${TRACE-0} == "1" ]];then set -o xtrace;fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"&&pwd -P)"
cd "$script_dir"||exit
DO_UPDATES=true
CLEAR_LAUNCHPAD=true
CLEAR_IOS=false
DRY_RUN=false
VERBOSE=false
CLEAR_CHROME=false
LOG_OUTPUT=false
UPDATE_MAMBA_ENVS=false
EXCLUDE_FORMULAE=()
EXCLUDE_CASKS=(font-comic-neue font-open-sans)
MAMBA_SKIP_ENVS=()
LOG_DIR="$HOME/Library/Logs/MacCleanup"
LOG_FILE="$LOG_DIR/cleanup_$(date +%Y%m%d_%H%M%S).log"
[[ -n ${args[--no-updates]} ]]&&DO_UPDATES=false
[[ -n ${args[--launchpad]} ]]&&CLEAR_LAUNCHPAD=true
[[ -n ${args[--chrome]} ]]&&CLEAR_CHROME=true
[[ -n ${args[--ios]} ]]&&CLEAR_IOS=true
[[ -n ${args[--mamba]} ]]&&UPDATE_MAMBA_ENVS=true
[[ -n ${args[--dry-run]} ]]&&DRY_RUN=true
[[ -n ${args[--verbose]} ]]&&VERBOSE=true
[[ -n ${args[--log]} ]]&&LOG_OUTPUT=true
set -o nounset
if [[ $VERBOSE == true ]];then
echo "Starting macOS Maid in verbose mode..."
fi
if command -v sudo >/dev/null 2>&1;then
printf "✨ Requesting administrative privileges...\n"
sudo -v
(while
true
do
sudo -n true
sleep 60
kill -0 "$$"||exit
done 2>/dev/null) \
&
fi
if $LOG_OUTPUT;then
mkdir -p "$LOG_DIR"
if ! $DRY_RUN;then
exec > >(tee -a "$LOG_FILE") 2>&1
printf "✨ Logging output to: %s\n" "$LOG_FILE"
fi
fi
sparkle(){
local format="$1"
shift
format="${format%\\n}"
printf "✨ $format\n" "$@"
}
bytes_to_human(){
local delta="${1:-0}" abs i frac
local -a UNITS=("Bytes" "KiB" "MiB" "GiB" "TiB")
abs=$((delta<0?-delta:delta))
i=0
frac=0
while ((abs>1024&&i<${#UNITS[@]}-1));do
frac=$((abs%1024*100/1024))
abs=$((abs/1024))
((i++))
done
if ((delta>=0));then
printf '%s.%02d %s freed up...\n' "$abs" "$frac" "${UNITS[i]}"
else
printf '%s.%02d %s consumed :(\n' "$abs" "$frac" "${UNITS[i]}"
fi
}
require_cmd(){
command -v "$1" >/dev/null 2>&1
}
safe_rm(){
if $DRY_RUN;then
printf '[DRY-RUN] Would remove: %s\n' "$*"
elif $VERBOSE;then
printf '[VERBOSE] Removing paths for: %s\n' "$*"
rm -rfv "$@"||true
else
rm -rf "$@" >/dev/null 2>&1||true
fi
}
safe_sudo_rm(){
if $DRY_RUN;then
printf '[DRY-RUN] Would sudo remove: %s\n' "$*"
elif $VERBOSE;then
printf '[VERBOSE] Sudo removing paths for: %s\n' "$*"
sudo rm -rfv "$@"||true
else
sudo rm -rf "$@" >/dev/null 2>&1||true
fi
}
run_cmd(){
local show_output=false
local run_in_bg=false
while [[ $# -gt 0 ]];do
case "$1" in
--show)show_output=true
shift
;;
--bg)run_in_bg=true
shift
;;
*)break
esac
done
if $DRY_RUN;then
if $run_in_bg;then
printf '[DRY-RUN] Would execute in background: %s\n' "$*"
else
printf '[DRY-RUN] Would execute: %s\n' "$*"
fi
elif $VERBOSE;then
if $run_in_bg;then
printf '[VERBOSE] Executing in background: %s\n' "$*"
"$@"&
else
printf '[VERBOSE] Executing: %s\n' "$*"
"$@"||true
fi
elif $show_output;then
if $run_in_bg;then
"$@"&
else
"$@"||true
fi
else
if $run_in_bg;then
"$@" >/dev/null 2>&1&
else
"$@" >/dev/null 2>&1||true
fi
fi
}
clean_safari_completely(){
sparkle "Deep Cleaning Safari..."
local was_killed=false
if pgrep -x "Safari" >/dev/null;then
was_killed=true
if ! $DRY_RUN;then
if $VERBOSE;then printf '[VERBOSE] Closing Safari...\n';fi
osascript -e 'quit app "Safari"' >/dev/null 2>&1||pkill -x "Safari"
local wait_count=0
while pgrep -x "Safari" >/dev/null&&((wait_count<10));do
sleep 0.5
((wait_count++))
done
else
printf '[DRY-RUN] Would close app: Safari\n'
fi
fi
safe_rm "$HOME/Library/Caches/com.apple.Safari"
safe_rm "$HOME/Library/Containers/com.apple.Safari/Data/Library/Caches"
local data_targets=(
"$HOME/Library/Cookies/Cookies.binarycookies"
"$HOME/Library/Safari/LocalStorage"
"$HOME/Library/Safari/Databases"
"$HOME/Library/Safari/Service Workers")
for target in "${data_targets[@]}";do
if [[ -d $target ]];then
safe_rm "$target/"*
elif [[ -f $target ]];then
safe_rm "$target"
fi
done
if $was_killed;then
if ! $DRY_RUN;then
sparkle "Relaunching Safari..."
run_cmd open -a "Safari"
else
printf '[DRY-RUN] Would relaunch app: Safari\n'
fi
fi
}
clean_chrome_completely(){
local chrome_base="$HOME/Library/Application Support/Google/Chrome"
if [[ ! -d $chrome_base ]];then
return 0
fi
sparkle "Deep Cleaning Google Chrome (All Profiles)..."
local was_killed=false
if pgrep -xi "Google Chrome" >/dev/null;then
was_killed=true
if ! $DRY_RUN;then
if $VERBOSE;then printf '[VERBOSE] Closing Google Chrome...\n';fi
pkill -xi "Google Chrome"
local wait_count=0
while pgrep -xi "Google Chrome" >/dev/null&&((wait_count<10));do
sleep 0.5
((wait_count++))
done
else
printf '[DRY-RUN] Would close app: Google Chrome\n'
fi
fi
safe_rm "$HOME/Library/Caches/Google/Chrome"
safe_rm "$chrome_base/Crashpad"
if require_cmd fd;then
mapfile -t chrome_profiles < <(fd -t d -d 1 '^(Default|Profile .*)$' "$chrome_base"||true)
else
mapfile -t chrome_profiles < <(find "$chrome_base" -maxdepth 1 -type d \( -name "Default" -o -name "Profile *" \)||true)
fi
for profile_dir in "${chrome_profiles[@]}";do
[[ -z $profile_dir ]]&&continue
local profile_name
profile_name="$(basename "$profile_dir")"
if $VERBOSE;then
printf '[VERBOSE] Purging data for Chrome profile: %s\n' "$profile_name"
fi
local cache_targets=("Cache" "Code Cache" "GPUCache" "DawnCache" "Service Worker/CacheStorage" "Service Worker/ScriptCache")
for sub in "${cache_targets[@]}";do
safe_rm "$profile_dir/$sub"
done
local data_targets=(
"Network/Cookies"
"Network/Cookies-journal"
"History"
"History-journal"
"History Provider Cache"
"Top Sites"
"Top Sites-journal"
"Visited Links"
"Local Storage"
"IndexedDB"
"Session Storage")
for sub in "${data_targets[@]}";do
safe_rm "$profile_dir/$sub"
done
done
if $was_killed;then
if ! $DRY_RUN;then
sparkle "Relaunching Google Chrome..."
run_cmd open -a "Google Chrome"
else
printf '[DRY-RUN] Would relaunch app: Google Chrome\n'
fi
fi
}
kib_free_before="$(df -kP /|awk 'NR==2{print $4}')"
bytes_free_before=$((kib_free_before*1024))
if require_cmd softwareupdate;then
sparkle "Checking macOS updates..."
run_cmd --show --bg sudo softwareupdate --background --force
su_output=$(sudo softwareupdate --list --all 2>&1||true)
if $VERBOSE;then
printf '[VERBOSE] %s\n' "$su_output"
fi
if grep -Fq "No new software available" <<<"$su_output";then
sparkle "macOS is already up to date."
else
if $DO_UPDATES;then
sparkle "Installing macOS updates..."
run_cmd --show sudo softwareupdate --install --all --agree-to-license
else
sparkle "macOS updates are available:"
printf '%s\n' "$su_output"
sparkle "DO_UPDATES is false. Skipping install..."
fi
fi
fi
if require_cmd brew;then
sparkle "Updating Homebrew..."
run_cmd brew update
sparkle "Upgrading formulae..."
if ((${#EXCLUDE_FORMULAE[@]}==0));then
run_cmd --show brew upgrade --formula||true
else
OUTDATED_FORMULAE=()
while IFS= read -r line;do
[[ -n $line ]]&&OUTDATED_FORMULAE+=("$line")
done < <(brew outdated --formula --greedy --quiet||true)
UPGRADE_FORMULAE=()
for pkg in "${OUTDATED_FORMULAE[@]}";do
if [[ " ${EXCLUDE_FORMULAE[*]-} " != *" $pkg "* ]];then
UPGRADE_FORMULAE+=("$pkg")
fi
done
if ((${#UPGRADE_FORMULAE[@]}>0));then
sparkle "Upgrading: ${UPGRADE_FORMULAE[*]}"
run_cmd --show brew upgrade --formula "${UPGRADE_FORMULAE[@]}"||true
else
sparkle "No formulae to upgrade"
fi
fi
sparkle "Upgrading Homebrew casks..."
if ((${#EXCLUDE_CASKS[@]}==0));then
run_cmd --show brew upgrade --greedy --cask||true
else
OUTDATED_CASKS=()
while IFS= read -r line;do
[[ -n $line ]]&&OUTDATED_CASKS+=("$line")
done < <(brew outdated --cask --greedy --quiet||true)
UPGRADE_CASKS=()
for pkg in "${OUTDATED_CASKS[@]}";do
if [[ " ${EXCLUDE_CASKS[*]-} " != *" $pkg "* ]];then
UPGRADE_CASKS+=("$pkg")
fi
done
if ((${#UPGRADE_CASKS[@]}>0));then
sparkle "Upgrading: ${UPGRADE_CASKS[*]}"
run_cmd --show brew upgrade --greedy --cask "${UPGRADE_CASKS[@]}"||true
else
sparkle "No casks to upgrade"
fi
fi
sparkle "Cleaning Homebrew cache..."
run_cmd --show brew tap --repair
run_cmd --show brew doctor
run_cmd brew cleanup --scrub --prune=all
bcache="$(brew --cache 2>/dev/null||true)"
if [[ -n $bcache ]];then
safe_rm "$bcache"
fi
sparkle "Done brewing..."
fi
if require_cmd zsh&&zsh -i -c 'command -v zimfw >/dev/null' >/dev/null 2>&1;then
sparkle "Upgrading Zim & Modules..."
if $DRY_RUN;then
printf '[DRY-RUN] Would update zimfw\n'
else
zsh -i -c "zimfw upgrade"|grep -v "Already up to date"||true
zsh -i -c "zimfw update"|grep -v "Already up to date"||true
fi
fi
if require_cmd tlmgr;then
sparkle "Updating TeX Live packages..."
if [[ -d /usr/local/texlive ]];then
run_cmd sudo chown -R "$(id -un):$(id -g)" /usr/local/texlive
fi
run_cmd --show sudo tlmgr update --self --all --reinstall-forcibly-removed
fi
if require_cmd mamba;then
sparkle "Updating base mamba environment..."
mamba update -n base -yq --all >/dev/null 2>&1||true
if $UPDATE_MAMBA_ENVS;then
if require_cmd jq;then
mapfile -t MAMBA_ENVS < <(mamba env list --json|jq -r '.envs[] | select(test("/envs/")) | split("/")[-1]'||true)
else
MAMBA_ENVS=()
while IFS= read -r p;do
[[ -n $p ]]&&MAMBA_ENVS+=("$(basename "$p")")
done < <(mamba env list 2>/dev/null|awk '/\/envs\//{print $NF}'||true)
fi
if ((${#MAMBA_ENVS[@]}>0));then
echo "Found ${#MAMBA_ENVS[@]} environments: ${MAMBA_ENVS[*]}"
fi
for env in "${MAMBA_ENVS[@]:-}";do
for skip in "${MAMBA_SKIP_ENVS[@]}";do
[[ $env == "$skip" ]]&&continue 2
done
sparkle "Updating mamba env: $env"
mamba update -n "$env" -y --all||true
done
fi
sparkle "Cleaning mamba caches..."
mamba clean -yq --all >/dev/null 2>&1||true
fi
if require_cmd npm;then
sparkle "Updating global npm packages & clearing cache..."
run_cmd npm install -g npm@latest
run_cmd --show npm update -g
run_cmd npm cache clean --force
fi
if require_cmd gem;then
sparkle "Updating Ruby gems..."
run_cmd --show gem update
sparkle "Updated Ruby gems..."
fi
if require_cmd uv;then
sparkle "Updating uv tools & python..."
run_cmd --show uv tool upgrade --all --pre
run_cmd --show uv python upgrade
sparkle "Pruning uv cache..."
run_cmd --show uv cache prune
fi
sparkle "Cleaning language package caches..."
if require_cmd python3;then run_cmd --show python3 -m pip cache purge;fi
if require_cmd cargo;then run_cmd --show cargo cache -a;fi
if require_cmd go;then run_cmd --show go clean -modcache;fi
if require_cmd gem;then run_cmd --show gem cleanup;fi
sparkle "Emptying Trash..."
safe_rm "$HOME/.Trash/"*
sparkle "Clearing system and user log files..."
safe_sudo_rm /var/log/*
safe_sudo_rm /Library/Logs/*
safe_rm "$HOME/Library/Logs/"*
sparkle "Clearing QuickLook and Font caches..."
run_cmd qlmanage -r cache
run_cmd atsutil databases -remove
sparkle "Thinning Time Machine local snapshots..."
run_cmd sudo tmutil thinlocalsnapshots / 10000000000 4
if require_cmd docker&&docker info >/dev/null 2>&1;then
sparkle "Docker is running. Pruning system & volumes..."
run_cmd docker system prune -f
run_cmd docker builder prune -f
run_cmd docker volume prune -f
fi
sparkle "Clearing Xcode Derived Data & Archives..."
safe_rm "$HOME/Library/Developer/Xcode/DerivedData/"*
safe_rm "$HOME/Library/Developer/Xcode/Archives/"*
safe_rm "$HOME/Library/Developer/CoreSimulator/Caches/"*
if $CLEAR_CHROME;then
clean_chrome_completely
clean_safari_completely
else
sparkle "Skipping Google Chrome clearing..."
fi
clean_electron_app(){
local base_path="$1"
local app_name="$2"
sparkle "Cleaning caches for: $app_name..."
local was_killed=false
local app_bundle=""
if pgrep -xi "$app_name" >/dev/null;then
was_killed=true
local pid
pid=$(pgrep -xi "$app_name"|head -n 1||true)
if [[ -n $pid ]];then
local exec_path
exec_path=$(ps -p "$pid" -o comm=||true)
if [[ $exec_path == *".app/"* ]];then
app_bundle="${exec_path%%.app/*}.app"
fi
fi
if ! $DRY_RUN;then
if $VERBOSE;then printf '[VERBOSE] Closing %s...\n' "$app_name";fi
pkill -xi "$app_name"
local wait_count=0
while pgrep -xi "$app_name" >/dev/null&&((wait_count<10));do
sleep 0.5
((wait_count++))
done
sparkle "Killed %s..." "$app_name"
else
printf '[DRY-RUN] Would close app: %s\n' "$app_name"
fi
fi
local targets=("Cache" "Code Cache" "GPUCache" "DawnCache" "Service Worker/CacheStorage" "Service Worker/ScriptCache")
for sub in "${targets[@]}";do
if [[ -d "$base_path/$sub" ]];then
safe_rm "$base_path/$sub"
fi
done
if [[ -d "$base_path/Partitions" ]];then
for partition in "$base_path/Partitions"/*;do
if [[ -d $partition ]];then
for sub in "${targets[@]}";do
if [[ -d "$partition/$sub" ]];then
safe_rm "$partition/$sub"
fi
done
fi
done
fi
if $was_killed;then
if ! $DRY_RUN;then
sparkle "Relaunching $app_name..."
if [[ -n $app_bundle && -e $app_bundle ]];then
run_cmd open "$app_bundle"
else
run_cmd open -a "$app_name"||true
fi
else
printf '[DRY-RUN] Would relaunch app: %s\n' "$app_name"
fi
fi
}
sparkle "Dynamically discovering Electron & Chromium app caches..."
if require_cmd fd;then
mapfile -t electron_apps < <(fd -t d -g "GPUCache" -d 3 "$HOME/Library/Application Support" -x dirname||true)
else
mapfile -t electron_apps < <(find "$HOME/Library/Application Support" -maxdepth 3 -type d -name "GPUCache" -prune|awk -F'/GPUCache' '{print $1}'||true)
fi
if ((${#electron_apps[@]}>0));then
mapfile -t unique_apps < <(printf "%s\n" "${electron_apps[@]}"|sort -u)
app_names=()
for app_path in "${unique_apps[@]}";do
app_name="$(basename "$app_path")"
if [[ $app_name == "Default" ]];then
app_name="$(basename "$(dirname "$app_path")")"
fi
app_names+=("$app_name")
done
sparkle "Discovered apps: ${app_names[*]}"
for i in "${!unique_apps[@]}";do
clean_electron_app "${unique_apps[$i]}" "${app_names[$i]}"
done
else
sparkle "No dynamic Electron apps found."
fi
if $CLEAR_IOS;then
sparkle "Clearing iOS/iPadOS Local Backups..."
safe_rm "$HOME/Library/Application Support/MobileSync/Backup/"*
fi
sparkle "Cleaning DNS cache..."
run_cmd dscacheutil -flushcache
run_cmd sudo killall -HUP mDNSResponder
if $CLEAR_LAUNCHPAD;then
sparkle "Clearing Launchpad..."
run_cmd defaults write com.apple.dock ResetLaunchPad -bool true
run_cmd killall Dock
fi
if $DRY_RUN;then
sparkle "Dry-run complete. No files were actually deleted."
else
sparkle "Cleanup Success!"
kib_free_after="$(df -kP /|awk 'NR==2{print $4}')"
bytes_free_after=$((kib_free_after*1024))
delta=$((bytes_free_after-bytes_free_before))
bytes_to_human "$delta"
if $LOG_OUTPUT;then
printf "\nDetailed log saved to: %s\n" "$LOG_FILE"
fi
fi
}
version_command(){
echo "$version"
}
maid.sh_usage(){
printf "maid.sh - macOS Maid - A Comprehensive Mac Cleanup Utility\n\n"
printf "%s\n" "Usage:"
printf "  maid.sh [OPTIONS]\n"
printf "  maid.sh --help | -h\n"
printf "  maid.sh --version\n"
echo
if [[ -n $long_usage ]];then
printf "%s\n" "Options:"
printf "  %s\n" "--no-updates, -u"
printf "    Do not install macOS updates\n"
echo
printf "  %s\n" "--launchpad, -l"
printf "    Clear Launchpad layout\n"
echo
printf "  %s\n" "--chrome, -c"
printf "    Clear Chrome\n"
echo
printf "  %s\n" "--ios, -i"
printf "    Clear iOS/iPadOS local backups\n"
echo
printf "  %s\n" "--mamba, -m"
printf "    Update Mamba environments\n"
echo
printf "  %s\n" "--dry-run, -n"
printf "    Dry-run (show what would be deleted without doing it)\n"
echo
printf "  %s\n" "--verbose, -v"
printf "    Verbose output (prints executed commands and removed paths)\n"
echo
printf "  %s\n" "--log, -o"
printf "    Log execution output\n"
echo
printf "  %s\n" "--help, -h"
printf "    Show this help\n"
echo
printf "  %s\n" "--version"
printf "    Show version number\n"
echo
fi
}
normalize_input(){
local arg passthru flags
passthru=false
while [[ $# -gt 0 ]];do
arg="$1"
if [[ $passthru == true ]];then
input+=("$arg")
elif [[ $arg =~ ^(--[a-zA-Z0-9_\-]+)=(.+)$ ]];then
input+=("${BASH_REMATCH[1]}")
input+=("${BASH_REMATCH[2]}")
elif [[ $arg =~ ^(-[a-zA-Z0-9])=(.+)$ ]];then
input+=("${BASH_REMATCH[1]}")
input+=("${BASH_REMATCH[2]}")
elif [[ $arg =~ ^-([a-zA-Z0-9][a-zA-Z0-9]+)$ ]];then
flags="${BASH_REMATCH[1]}"
for ((i=0; i<${#flags}; i++));do
input+=("-${flags:i:1}")
done
elif [[ $arg == "--" ]];then
passthru=true
input+=("$arg")
else
input+=("$arg")
fi
shift
done
}
parse_requirements(){
local key
while [[ $# -gt 0 ]];do
key="$1"
case "$key" in
--version)version_command
exit
;;
--help|-h)long_usage=yes
maid.sh_usage
exit
;;
*)break
esac
done
action="root"
while [[ $# -gt 0 ]];do
key="$1"
case "$key" in
--no-updates|-u)args['--no-updates']=1
shift
;;
--launchpad|-l)args['--launchpad']=1
shift
;;
--chrome|-c)args['--chrome']=1
shift
;;
--ios|-i)args['--ios']=1
shift
;;
--mamba|-m)args['--mamba']=1
shift
;;
--dry-run|-n)args['--dry-run']=1
shift
;;
--verbose|-v)args['--verbose']=1
shift
;;
--log|-o)args['--log']=1
shift
;;
-?*)printf "invalid option: %s\n" "$key" >&2
exit 1
;;
*)printf "invalid argument: %s\n" "$key" >&2
exit 1
esac
done
}
initialize(){
declare -g version="1.0.0"
set -eo pipefail
}
run(){
declare -g long_usage=''
declare -g -A args=()
declare -g -A deps=()
declare -g -a env_var_names=()
declare -g -a input=()
normalize_input "$@"
parse_requirements "${input[@]}"
case "$action" in
"root")root_command
esac
}
command_line_args=("$@")
initialize
run "${command_line_args[@]}"
