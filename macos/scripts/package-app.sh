#!/bin/bash
set -euo pipefail

# Packages a built Shiftland.app into the files a GitHub release offers:
# Shiftland.dmg, Shiftland.zip, and SHA256SUMS.txt in .build/dist/.
#
# Usage: package-app.sh [app] [output directory]
#
# Set SHIFTLAND_SIGN_IDENTITY to the Developer ID Application identity that
# signed the app to sign the disk image too. Notarization runs when these are
# set as well, using an App Store Connect API key:
#   SHIFTLAND_NOTARY_KEY_PATH   path to the key's .p8 file
#   SHIFTLAND_NOTARY_KEY_ID     the key ID
#   SHIFTLAND_NOTARY_ISSUER_ID  the issuer ID

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
repository_root="$(cd "$project_directory/.." && pwd)"
info_plist="$project_directory/Resources/Info.plist"
bundle_name="$(/usr/libexec/PlistBuddy -c 'Print CFBundleName' "$info_plist")"
app="${1:-$repository_root/.build/$bundle_name.app}"
output="${2:-$repository_root/.build/dist}"
sign_identity="${SHIFTLAND_SIGN_IDENTITY:--}"

notarize=0
if [[ -n "${SHIFTLAND_NOTARY_KEY_PATH:-}" ]]; then
    if [[ "$sign_identity" == "-" ]]; then
        echo "Notarization needs an app signed with a Developer ID Application identity." >&2
        exit 1
    fi
    : "${SHIFTLAND_NOTARY_KEY_ID:?Set SHIFTLAND_NOTARY_KEY_ID to notarize}"
    : "${SHIFTLAND_NOTARY_ISSUER_ID:?Set SHIFTLAND_NOTARY_ISSUER_ID to notarize}"
    notarize=1
fi

if [[ ! -d "$app" ]]; then
    echo "No app at $app. Run scripts/build-app.sh first." >&2
    exit 1
fi
codesign --verify --strict "$app"

mkdir -p "$repository_root/.build"
work="$(mktemp -d "$repository_root/.build/package.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT
rm -rf "$output"
mkdir -p "$output"
app_name="$(basename "$app")"
staged_app="$work/$app_name"
ditto "$app" "$staged_app"

notarize_file() {
    local file="$1"
    local result="$work/notary-result.json"
    local status submission
    echo "Submitting $(basename "$file") for notarization…"
    xcrun notarytool submit "$file" \
        --key "$SHIFTLAND_NOTARY_KEY_PATH" \
        --key-id "$SHIFTLAND_NOTARY_KEY_ID" \
        --issuer "$SHIFTLAND_NOTARY_ISSUER_ID" \
        --wait --timeout 30m --output-format json >"$result" || true
    if ! status="$(plutil -extract status raw -o - "$result" 2>/dev/null)"; then
        echo "notarytool did not return a result:" >&2
        cat "$result" >&2
        exit 1
    fi
    if [[ "$status" != "Accepted" ]]; then
        echo "Apple's notary service returned $status for $(basename "$file")." >&2
        if submission="$(plutil -extract id raw -o - "$result" 2>/dev/null)"; then
            xcrun notarytool log "$submission" \
                --key "$SHIFTLAND_NOTARY_KEY_PATH" \
                --key-id "$SHIFTLAND_NOTARY_KEY_ID" \
                --issuer "$SHIFTLAND_NOTARY_ISSUER_ID" >&2 || true
        fi
        exit 1
    fi
}

# Notarize the app itself and staple the ticket so it opens offline, even after
# it leaves the disk image. The notary service needs a zip; stapler needs the app.
if ((notarize)); then
    ditto -c -k --keepParent "$staged_app" "$work/notarization.zip"
    notarize_file "$work/notarization.zip"
    xcrun stapler staple "$staged_app"
    xcrun stapler validate "$staged_app"
fi
ditto -c -k --keepParent "$staged_app" "$output/$bundle_name.zip"

dmg="$output/$bundle_name.dmg"
dmg_root="$work/dmg"
mkdir -p "$dmg_root"
ditto "$staged_app" "$dmg_root/$app_name"
ln -s /Applications "$dmg_root/Applications"
# hdiutil sometimes reports "Resource busy" on CI machines, so retry.
for attempt in 1 2 3 4 5; do
    if hdiutil create -volname "$bundle_name" -srcfolder "$dmg_root" \
        -fs HFS+ -format UDZO -ov "$dmg"; then
        break
    fi
    if ((attempt == 5)); then
        echo "hdiutil could not create $dmg." >&2
        exit 1
    fi
    sleep $((attempt * 5))
done

if [[ "$sign_identity" != "-" ]]; then
    codesign --force --timestamp --sign "$sign_identity" "$dmg"
    codesign --verify --strict "$dmg"
fi
if ((notarize)); then
    notarize_file "$dmg"
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    spctl --assess --type execute --verbose=2 "$staged_app"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
fi

(cd "$output" && shasum -a 256 "$bundle_name.dmg" "$bundle_name.zip" >SHA256SUMS.txt)
cat "$output/SHA256SUMS.txt"
