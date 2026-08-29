#!/bin/bash
set -euo pipefail

output_path="${1:?usage: scripts/capture-screenshot.sh OUTPUT.png [SCALE]}"
capture_scale="${2:-2}"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$(mktemp -d "${TMPDIR:-/tmp}/ai-observatory.XXXXXX")"
capture_copy=""
capture_root="$repo_root"
capture_app=""

cleanup() {
  rm -rf "$derived_data"
  if [[ -n "$capture_copy" ]]; then
    rm -rf "$capture_copy"
  fi
  if [[ -n "$capture_app" ]]; then
    rm -rf "$capture_app"
  fi
}
trap cleanup EXIT

build_capture_app() {
  xcodebuild \
    -project "$capture_root/AIObservatory.xcodeproj" \
    -scheme AIObservatory \
    -configuration Debug \
    -derivedDataPath "$derived_data" \
    build >/dev/null
}

if ! build_capture_app; then
  capture_copy="$(mktemp -d "${TMPDIR:-/tmp}/ai-observatory-source.XXXXXX")"
  cp -R "$repo_root/." "$capture_copy/"
  mv "$capture_copy/AIObservatory/AppIcon.icon" "$capture_copy/AppIcon.icon.disabled"
  mkdir -p "$capture_copy/AIObservatory/Assets.xcassets/AppIcon.appiconset"
  cp "$repo_root/ai-usage-monitor-artwork.png" \
    "$capture_copy/AIObservatory/Assets.xcassets/AppIcon.appiconset/appicon.png"
  cp "$repo_root/scripts/capture-appicon-contents.json" \
    "$capture_copy/AIObservatory/Assets.xcassets/AppIcon.appiconset/Contents.json"
  capture_root="$capture_copy"
  build_capture_app
fi

run_capture() {
  local app_bundle="$1"
  local log_suffix="$2"

  open -n -W \
    --env AI_OBSERVATORY_CAPTURE_SCALE="$capture_scale" \
    --env AI_OBSERVATORY_SNAPSHOT=healthy \
    --env AI_OBSERVATORY_SCREENSHOT_PATH="$output_path" \
    --stdout "$derived_data/capture-$log_suffix.stdout" \
    --stderr "$derived_data/capture-$log_suffix.stderr" \
    "$app_bundle" >/dev/null || return 1
  test -s "$output_path"
}

if ! run_capture "$derived_data/Build/Products/Debug/AIObservatory.app" direct; then
  capture_app="/Applications/AI Observatory Capture $(basename "$derived_data").app"
  if [[ -e "$capture_app" ]]; then
    echo "Capture app path already exists: $capture_app" >&2
    exit 1
  fi
  ditto "$derived_data/Build/Products/Debug/AIObservatory.app" "$capture_app"
  run_capture "$capture_app" installed
fi

cat "$derived_data/capture-direct.stdout" "$derived_data/capture-direct.stderr" 2>/dev/null || true
cat "$derived_data/capture-installed.stdout" "$derived_data/capture-installed.stderr" 2>/dev/null || true

test -s "$output_path"
echo "Wrote $output_path"
