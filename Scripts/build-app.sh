#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"
cd "$eave_root"
configuration="${1:-release}"
case "$configuration" in debug|release) ;; *) eave_fail "Usage: $0 [debug|release] [--signed]" ;; esac
if [[ $# -gt 0 ]]; then shift; fi
eave_parse_distribution_options "$@"
[[ "$eave_dmg" == false ]] || eave_fail 'Use package.sh --dmg to create a disk image.'
eave_read_version
eave_require swift
eave_require codesign
if pgrep -x Eave >/dev/null 2>&1; then eave_fail 'Quit Eave before replacing dist/Eave.app.'; fi
if [[ "$eave_signed" == true ]]; then
    eave_require_signing_identity
elif [[ -n "${SIGNING_IDENTITY:-}" && "$SIGNING_IDENTITY" != - ]]; then
    eave_fail 'SIGNING_IDENTITY is set. Pass --signed, or unset it for an ad-hoc build.'
fi

swift build -c "$configuration" --arch arm64
binary_directory="$(swift build -c "$configuration" --arch arm64 --show-bin-path)"
[[ ! -L dist ]] || eave_fail 'Refusing to write build products through a symlinked dist directory.'
mkdir -p dist
task_directory="$(mktemp -d "$eave_root/dist/.bundle.XXXXXX")"
trap 'rm -rf "$task_directory"' EXIT
staged_app="$task_directory/Eave.app"
app_directory="$eave_root/dist/Eave.app"
[[ ! -L "$app_directory" ]] || eave_fail 'Refusing to replace a symlinked Eave.app.'
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_directory/Eave" "$staged_app/Contents/MacOS/Eave"
if [[ "$configuration" == release ]]; then
    # SwiftPM/Xcode can retain absolute source/object paths in its debug map.
    # Remove that metadata from distributions before the final bundle signature.
    eave_require xcrun
    xcrun strip -S "$staged_app/Contents/MacOS/Eave"
fi
cp Resources/Eave.icns "$staged_app/Contents/Resources/Eave.icns"
cp "$eave_plist" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $eave_bundle_identifier" "$staged_app/Contents/Info.plist"
if [[ "$eave_signed" == true ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp --entitlements Resources/Eave.entitlements "$staged_app"
    eave_validate_bundle "$staged_app" signed
else
    codesign --force --sign - --entitlements Resources/Eave.entitlements "$staged_app"
    eave_validate_bundle "$staged_app" adhoc
fi
if [[ -e "$app_directory" ]]; then mv "$app_directory" "$task_directory/previous.app"; fi
if ! mv "$staged_app" "$app_directory"; then
    if [[ -e "$task_directory/previous.app" ]]; then mv "$task_directory/previous.app" "$app_directory"; fi
    eave_fail 'Could not install the newly built bundle in dist.'
fi
echo "Built $app_directory (version $eave_version, build $eave_build)"
if [[ "$eave_signed" == false ]]; then echo 'Ad-hoc signed for local testing; not notarized.'; fi
