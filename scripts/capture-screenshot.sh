#!/bin/bash
set -euo pipefail

output_path="${1:?usage: scripts/capture-screenshot.sh OUTPUT.png [SCALE]}"
capture_scale="${2:-2}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$(mktemp -d "${TMPDIR:-/tmp}/ai-observatory.XXXXXX")"
app_path="$derived_data/Build/Products/Debug/AIObservatory.app/Contents/MacOS/AIObservatory"

trap 'rm -rf "$derived_data"' EXIT

xcodebuild \
  -project "$repo_root/AIObservatory.xcodeproj" \
  -scheme AIObservatory \
  -configuration Debug \
  -derivedDataPath "$derived_data" \
  build >/dev/null

AI_OBSERVATORY_CAPTURE_SCALE="$capture_scale" \
AI_OBSERVATORY_SNAPSHOT=healthy \
AI_OBSERVATORY_SCREENSHOT_PATH="$output_path" \
  "$app_path" >/dev/null 2>&1

test -s "$output_path"
echo "Wrote $output_path"
