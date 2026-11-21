#!/bin/bash
set -euo pipefail

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
repository_root="$(cd "$project_directory/.." && pwd)"
cd "$project_directory"
info_plist="$project_directory/Resources/Info.plist"
bundle_name="$(/usr/libexec/PlistBuddy -c 'Print CFBundleName' "$info_plist")"
executable_name="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$info_plist")"
swift build -j 2 --product "$executable_name"
executable_directory="$(swift build --show-bin-path)"
bundle="$repository_root/.build/$bundle_name.app"
resources="$bundle/Contents/Resources"
icon_source="$project_directory/Resources/Brand/AppIcon.png"
icon_file="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' "$info_plist")"
mkdir -p "$repository_root/.build"
icon_work="$(mktemp -d "$repository_root/.build/app-icon.XXXXXXXX")"
trap 'rm -rf "$icon_work"' EXIT

iconset="$icon_work/AppIcon.iconset"
mkdir -p "$iconset" "$bundle/Contents/MacOS" "$resources"
install -m 0644 "$project_directory/Resources/Brand/AppIcon-16.png" "$iconset/icon_16x16.png"
install -m 0644 "$project_directory/Resources/Brand/AppIcon-16@2x.png" "$iconset/icon_16x16@2x.png"
for icon_size in 32 128 256 512; do
    retina_size=$((icon_size * 2))
    sips -z "$icon_size" "$icon_size" "$icon_source" \
        --out "$iconset/icon_${icon_size}x${icon_size}.png" >/dev/null
    sips -z "$retina_size" "$retina_size" "$icon_source" \
        --out "$iconset/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil --convert icns --output "$resources/$icon_file" "$iconset"
install -m 0755 "$executable_directory/$executable_name" "$bundle/Contents/MacOS/$executable_name"
install -m 0644 "$info_plist" "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
printf '%s\n' "$bundle"
