#!/bin/bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$repo_root/build"
built_app="$derived_data/Build/Products/Release/AIUsageObservatory.app"
applications_dir="/Applications"
installed_app="$applications_dir/AI Usage Observatory.app"
legacy_app="${HOME}/Applications/AI Usage Observatory.app"
legacy_executable="$legacy_app/Contents/MacOS/AIUsageObservatory"

find_legacy_pids() {
  pgrep -f "$legacy_executable" 2>/dev/null
}

xcodebuild \
  -project "$repo_root/AIUsageObservatory.xcodeproj" \
  -scheme AIUsageObservatory \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  build

test -d "$built_app"
test -f "$built_app/Contents/Info.plist"

if [ -w "$applications_dir" ]; then
  rm -rf "$installed_app"
  ditto "$built_app" "$installed_app"
else
  sudo rm -rf "$installed_app"
  sudo ditto "$built_app" "$installed_app"
fi

test -d "$installed_app"

if [ -d "$legacy_app" ]; then
  if legacy_pids="$(find_legacy_pids)"; then
    echo "Requesting a clean quit from the legacy installation..."
    osascript -e 'tell application id "nl.wavesweb.AIUsageObservatory" to quit'
    for _ in {1..10}; do
      if legacy_pids="$(find_legacy_pids)"; then
        sleep 1
      else
        pgrep_exit=$?
        if [ "$pgrep_exit" -eq 1 ]; then
          break
        fi
        echo "Unable to determine whether the legacy installation is still running; no cleanup was performed." >&2
        exit 1
      fi
    done
    if legacy_pids="$(find_legacy_pids)"; then
      echo "The legacy installation is still running; quit it manually, then rerun this script." >&2
      exit 1
    else
      pgrep_exit=$?
      if [ "$pgrep_exit" -ne 1 ]; then
        echo "Unable to determine whether the legacy installation is still running; no cleanup was performed." >&2
        exit 1
      fi
    fi
  else
    pgrep_exit=$?
    if [ "$pgrep_exit" -ne 1 ]; then
      echo "Unable to determine whether the legacy installation is running; no cleanup was performed." >&2
      exit 1
    fi
  fi
  rm -rf "$legacy_app"
fi

echo "Built:     $built_app"
echo "Installed: $installed_app"
