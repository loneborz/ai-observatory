#!/bin/bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="$repo_root/build"
built_app="$derived_data/Build/Products/Release/AIUsageObservatory.app"
applications_dir="${HOME}/Applications"
installed_app="$applications_dir/AI Usage Observatory.app"

xcodebuild \
  -project "$repo_root/AIUsageObservatory.xcodeproj" \
  -scheme AIUsageObservatory \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  build

test -d "$built_app"
mkdir -p "$applications_dir"
rm -rf "$installed_app"
ditto "$built_app" "$installed_app"

echo "Built:     $built_app"
echo "Installed: $installed_app"
