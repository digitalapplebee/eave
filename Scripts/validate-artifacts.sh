#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
eave_read_version
artifact_directory="$eave_root/dist/release"
mode=adhoc
while [[ $# -gt 0 ]]; do
    case "$1" in
        --signed) mode=signed; shift ;;
        --directory) [[ $# -ge 2 ]] || eave_fail '--directory requires a path.'; artifact_directory="$2"; shift 2 ;;
        *) eave_fail "Unknown validation argument: $1" ;;
    esac
done
[[ -d "$artifact_directory" ]] || eave_fail "Missing artifact directory: $artifact_directory"
artifact_directory="$(cd "$artifact_directory" && pwd)"
archive_name="Eave-v$eave_version.zip"
image_name="Eave-v$eave_version.dmg"
[[ -f "$artifact_directory/SHA256SUMS.txt" && -f "$artifact_directory/$archive_name" ]] || eave_fail 'Missing versioned ZIP or SHA256SUMS.txt.'
zip_count=0
dmg_count=0
while read -r checksum name extra; do
    [[ "$checksum" =~ ^[0-9a-fA-F]{64}$ && -z "$extra" ]] || eave_fail 'Invalid checksum manifest format.'
    case "$name" in
        "$archive_name") zip_count=$((zip_count + 1)) ;;
        "$image_name") dmg_count=$((dmg_count + 1)) ;;
        *) eave_fail "Unexpected checksum filename: $name" ;;
    esac
done < "$artifact_directory/SHA256SUMS.txt"
[[ "$zip_count" == 1 && "$dmg_count" -le 1 ]] || eave_fail 'Checksum manifest must list the ZIP exactly once and DMG at most once.'
for artifact in "$artifact_directory"/*; do
    case "$(basename "$artifact")" in
        "$archive_name"|SHA256SUMS.txt) ;;
        "$image_name") [[ "$dmg_count" == 1 ]] || eave_fail 'The DMG is missing from SHA256SUMS.txt.' ;;
        *) eave_fail "Unexpected release artifact: $(basename "$artifact")" ;;
    esac
done
(cd "$artifact_directory" && shasum -a 256 -c SHA256SUMS.txt)
mkdir -p "$eave_root/.build"
task_directory="$(mktemp -d "$eave_root/.build/artifact-validation.XXXXXX")"
image_mounted=false
cleanup() {
    if [[ "$image_mounted" == true ]]; then hdiutil detach "$task_directory/mounted" >/dev/null; fi
    rm -rf "$task_directory"
}
trap cleanup EXIT
while IFS= read -r entry; do
    case "$entry" in
        /*|../*|*/../*|*/..) eave_fail 'Unsafe path in ZIP archive.' ;;
        Eave.app|Eave.app/*|LICENSE|INSTALL.txt|__MACOSX/*) ;;
        *) eave_fail "Unexpected ZIP root: $entry" ;;
    esac
done < <(zipinfo -1 "$artifact_directory/$archive_name")
ditto -x -k "$artifact_directory/$archive_name" "$task_directory/extracted"
eave_validate_distribution_bundle "$task_directory/extracted/Eave.app" "$mode"
cmp -s "$eave_root/LICENSE" "$task_directory/extracted/LICENSE" || eave_fail 'ZIP is missing the reviewed project license.'
[[ -s "$task_directory/extracted/INSTALL.txt" ]] || eave_fail 'ZIP is missing installation instructions.'
if [[ "$mode" == signed ]]; then
    xcrun stapler validate "$task_directory/extracted/Eave.app"
    spctl --assess --type execute --verbose=2 "$task_directory/extracted/Eave.app"
fi
if [[ "$dmg_count" == 1 ]]; then
    hdiutil verify "$artifact_directory/$image_name"
    mkdir -p "$task_directory/mounted"
    hdiutil attach "$artifact_directory/$image_name" -readonly -nobrowse -mountpoint "$task_directory/mounted" >/dev/null
    image_mounted=true
    eave_validate_distribution_bundle "$task_directory/mounted/Eave.app" "$mode"
    cmp -s "$eave_root/LICENSE" "$task_directory/mounted/LICENSE" || eave_fail 'DMG is missing the reviewed project license.'
    [[ -s "$task_directory/mounted/INSTALL.txt" ]] || eave_fail 'DMG is missing installation instructions.'
    [[ "$(readlink "$task_directory/mounted/Applications")" == /Applications ]] || eave_fail 'DMG is missing the Applications shortcut.'
    if [[ "$mode" == signed ]]; then
        codesign --verify --strict "$artifact_directory/$image_name"
        xcrun stapler validate "$artifact_directory/$image_name"
        xcrun stapler validate "$task_directory/mounted/Eave.app"
        spctl --assess --type open --context context:primary-signature --verbose=2 "$artifact_directory/$image_name"
    fi
    hdiutil detach "$task_directory/mounted" >/dev/null
    image_mounted=false
fi
echo "Validated Eave v$eave_version ($mode, arm64)."
