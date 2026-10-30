#!/bin/bash
# Shared helpers for local build products. Source this file; do not execute it.

eave_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eave_plist="$eave_root/Resources/Info.plist"

eave_fail() { echo "Eave: $*" >&2; exit 1; }

eave_require() {
    command -v "$1" >/dev/null 2>&1 || eave_fail "Required tool is unavailable: $1"
}

eave_read_version() {
    eave_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$eave_plist")"
    eave_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$eave_plist")"
    local version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
    [[ "$eave_version" =~ $version_pattern ]] || eave_fail 'CFBundleShortVersionString must be a numeric semantic version (X.Y.Z).'
    [[ "$eave_build" =~ ^[1-9][0-9]*$ ]] || eave_fail 'CFBundleVersion must be a positive integer.'
    if [[ -n "${EXPECTED_VERSION:-}" && "${EXPECTED_VERSION#v}" != "$eave_version" ]]; then
        eave_fail "Expected version ${EXPECTED_VERSION#v}, but Info.plist contains $eave_version."
    fi
    eave_bundle_identifier="${BUNDLE_ID:-com.eaveapp.Eave}"
    [[ "$eave_bundle_identifier" =~ ^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+$ ]] || eave_fail 'BUNDLE_ID must be a reverse-domain identifier.'
}

eave_parse_distribution_options() {
    eave_signed=false
    eave_dmg=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --signed) eave_signed=true ;;
            --dmg) eave_dmg=true ;;
            *) eave_fail "Unknown argument: $1. Supported options: --signed --dmg" ;;
        esac
        shift
    done
}

eave_require_signing_identity() {
    [[ "${SIGNING_IDENTITY:-}" == 'Developer ID Application: '* ]] || eave_fail 'Signed mode requires SIGNING_IDENTITY naming a Developer ID Application certificate.'
    local identities
    identities="$(security find-identity -v -p codesigning)"
    [[ "$identities" == *"\"$SIGNING_IDENTITY\""* ]] || eave_fail 'The requested Developer ID Application identity is not available in the keychain.'
}

eave_validate_bundle() {
    local bundle="$1" mode="$2" info="$1/Contents/Info.plist" signature architectures
    [[ -d "$bundle" && -x "$bundle/Contents/MacOS/Eave" ]] || eave_fail "Missing executable application bundle: $bundle"
    plutil -lint "$info" >/dev/null
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")" == "$eave_bundle_identifier" ]] || eave_fail 'Bundle identifier does not match BUNDLE_ID.'
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")" == "$eave_version" ]] || eave_fail 'Bundle version does not match Info.plist. Rebuild the app.'
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")" == "$eave_build" ]] || eave_fail 'Bundle build number does not match Info.plist. Rebuild the app.'
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$info")" == true ]] || eave_fail 'Bundle must be configured as a menu bar agent.'
    architectures="$(lipo -archs "$bundle/Contents/MacOS/Eave")"
    [[ "$architectures" == arm64 ]] || eave_fail "Unexpected application architecture: $architectures"
    codesign --verify --deep --strict "$bundle"
    signature="$(codesign --display --verbose=4 "$bundle" 2>&1)"
    if [[ "$mode" == signed ]]; then
        [[ "$signature" == *'Authority=Developer ID Application:'* ]] || eave_fail 'A Developer ID Application signature is required.'
        [[ "$signature" == *'flags='*'runtime'* ]] || eave_fail 'The signed app must use Hardened Runtime.'
        [[ "$signature" == *'Timestamp='* ]] || eave_fail 'The signed app must include a secure timestamp.'
    else
        [[ "$signature" == *'Signature=adhoc'* ]] || eave_fail 'Expected an ad-hoc development bundle; use --signed for Developer ID distribution.'
    fi
}

eave_validate_distribution_bundle() {
    eave_validate_bundle "$@"
    # Reject a Debug/unstripped app before it becomes a downloadable artifact.
    # Read nm's full output, and fail closed if the inspection itself fails.
    local symbols
    if ! symbols="$(xcrun nm -ap "$1/Contents/MacOS/Eave")"; then
        eave_fail 'Could not inspect the executable debug map.'
    fi
    if awk '$2 == "-" && ($5 == "SO" || $5 == "OSO") { found = 1 } END { exit !found }' <<< "$symbols"; then
        eave_fail 'The app contains a development debug map. Build Release before packaging a distribution.'
    fi
}

eave_notarize() {
    local artifact="$1" result="$2" status submission
    local arguments=(--keychain-profile "$NOTARY_PROFILE")
    if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then arguments+=(--keychain "$NOTARY_KEYCHAIN"); fi
    xcrun notarytool submit "$artifact" "${arguments[@]}" --wait --output-format json > "$result"
    status="$(plutil -extract status raw -o - "$result")"
    submission="$(plutil -extract id raw -o - "$result")"
    [[ "$status" == Accepted ]] || eave_fail "Notarization status: $status (submission $submission). Review the Apple notary log before distributing."
    echo "Apple notarization accepted: $submission"
}
