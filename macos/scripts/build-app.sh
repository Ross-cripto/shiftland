#!/bin/bash
set -euo pipefail

# Builds .build/Shiftland.app. With no settings, it makes a debug build for this
# Mac's architecture and signs it ad hoc. The release workflow sets:
#   SHIFTLAND_CONFIGURATION  debug (default) or release
#   SHIFTLAND_UNIVERSAL      1 to build one binary for Apple silicon and Intel
#   SHIFTLAND_VERSION        CFBundleShortVersionString, such as 0.2.0
#   SHIFTLAND_BUILD_NUMBER   CFBundleVersion
#   SHIFTLAND_SIGN_IDENTITY  codesign identity; "-" (default) signs ad hoc

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
repository_root="$(cd "$project_directory/.." && pwd)"
cd "$project_directory"
configuration="${SHIFTLAND_CONFIGURATION:-debug}"
sign_identity="${SHIFTLAND_SIGN_IDENTITY:--}"
case "$configuration" in
    debug | release) ;;
    *) echo "SHIFTLAND_CONFIGURATION must be debug or release, not $configuration" >&2; exit 1 ;;
esac

info_plist="$project_directory/Resources/Info.plist"
bundle_name="$(/usr/libexec/PlistBuddy -c 'Print CFBundleName' "$info_plist")"
executable_name="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$info_plist")"
bundle="$repository_root/.build/$bundle_name.app"
resources="$bundle/Contents/Resources"
icon_source="$project_directory/Resources/Brand/AppIcon.png"
icon_file="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' "$info_plist")"
mkdir -p "$repository_root/.build"
work="$(mktemp -d "$repository_root/.build/app-build.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT

if [[ "${SHIFTLAND_UNIVERSAL:-0}" == 1 ]]; then
    architecture_executables=()
    for architecture in arm64 x86_64; do
        swift build -j 2 -c "$configuration" --arch "$architecture" --product "$executable_name"
        architecture_directory="$(swift build -c "$configuration" --arch "$architecture" --show-bin-path)"
        architecture_executables+=("$architecture_directory/$executable_name")
    done
    executable="$work/$executable_name"
    lipo -create -output "$executable" "${architecture_executables[@]}"
else
    swift build -j 2 -c "$configuration" --product "$executable_name"
    executable="$(swift build -c "$configuration" --show-bin-path)/$executable_name"
fi

iconset="$work/AppIcon.iconset"
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
install -m 0755 "$executable" "$bundle/Contents/MacOS/$executable_name"
install -m 0644 "$info_plist" "$bundle/Contents/Info.plist"
if [[ -n "${SHIFTLAND_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHIFTLAND_VERSION" "$bundle/Contents/Info.plist"
fi
if [[ -n "${SHIFTLAND_BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SHIFTLAND_BUILD_NUMBER" "$bundle/Contents/Info.plist"
fi

if [[ "$sign_identity" == "-" ]]; then
    codesign --force --sign - "$bundle"
else
    # Notarization requires the hardened runtime and a secure timestamp.
    codesign --force --options runtime --timestamp --sign "$sign_identity" "$bundle"
fi
codesign --verify --strict "$bundle"
printf '%s\n' "$bundle"
