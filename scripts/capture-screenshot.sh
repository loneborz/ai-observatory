#!/bin/bash
set -euo pipefail

output_path="${1:?usage: scripts/capture-screenshot.sh OUTPUT.png}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$(mktemp -d "${TMPDIR:-/tmp}/ai-usage-observatory.XXXXXX")"
app_path="$derived_data/Build/Products/Debug/AIUsageObservatory.app/Contents/MacOS/AIUsageObservatory"

trap 'rm -rf "$derived_data"' EXIT

xcodebuild \
  -project "$repo_root/AIUsageObservatory.xcodeproj" \
  -scheme AIUsageObservatory \
  -configuration Debug \
  -derivedDataPath "$derived_data" \
  build >/dev/null

AI_USAGE_OBSERVATORY_SNAPSHOT=healthy \
AI_USAGE_OBSERVATORY_SCREENSHOT_PATH="$output_path" \
  "$app_path" >/dev/null 2>&1

test -s "$output_path"
echo "Wrote $output_path"
