#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$eave_root"
eave_parse_distribution_options "$@"
eave_read_version
eave_require ditto
eave_require shasum
eave_require zipinfo
[[ -f "$eave_root/LICENSE" ]] || eave_fail 'A reviewed LICENSE file is required before packaging a distribution.'
mode=adhoc
if [[ "$eave_signed" == true ]]; then
    mode=signed
    [[ -n "${NOTARY_PROFILE:-}" ]] || eave_fail 'Signed distribution requires a valid NOTARY_PROFILE stored with notarytool.'
    eave_require xcrun
    if [[ "$eave_dmg" == true ]]; then eave_require_signing_identity; fi
fi
if [[ "$eave_dmg" == true ]]; then eave_require hdiutil; fi
[[ ! -L dist ]] || eave_fail 'Refusing a symlinked dist directory.'
eave_validate_distribution_bundle "$eave_root/dist/Eave.app" "$mode"
task_directory="$(mktemp -d "$eave_root/dist/.package.XXXXXX")"
trap 'rm -rf "$task_directory"' EXIT
mkdir -p "$task_directory/output" "$task_directory/distribution"
ditto "$eave_root/dist/Eave.app" "$task_directory/Eave.app"

if [[ "$eave_signed" == true ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$task_directory/Eave.app" "$task_directory/notary-input.zip"
    eave_notarize "$task_directory/notary-input.zip" "$task_directory/app-notary-result.json"
    xcrun stapler staple "$task_directory/Eave.app"
    xcrun stapler validate "$task_directory/Eave.app"
    spctl --assess --type execute --verbose=2 "$task_directory/Eave.app"
fi

archive_name="Eave-v$eave_version.zip"
ditto "$task_directory/Eave.app" "$task_directory/distribution/Eave.app"
cp "$eave_root/LICENSE" "$task_directory/distribution/LICENSE"
cat > "$task_directory/distribution/INSTALL.txt" <<EOF
Eave $eave_version — Make your Mac yours.

Requires an Apple Silicon Mac with macOS 26 or later. Runtime verification is
limited; see the project's compatibility and manual validation documentation.

1. Move Eave.app to Applications, then open it.
2. Click Eave's icon in the macOS menu bar. The app does not stay in the Dock.
3. Enable customization for a supported local still wallpaper. Dynamic/Aerial
   wallpapers are left untouched when their configuration cannot be preserved.
4. Before uninstalling: disable Eave, visit each changed Space to restore its
   original wallpaper, disable Launch at Login, then quit and remove Eave.app.

Keep Eave's Application Support recovery folder while any Space still uses an
Eave-generated wallpaper. Never delete your original wallpaper files.

EOF
if [[ "$eave_signed" == true ]]; then
    cat >> "$task_directory/distribution/INSTALL.txt" <<'EOF'
This artifact was Developer ID signed, notarized, and stapled by the release
packaging process. macOS may still ask you to confirm its first launch.
EOF
else
    cat >> "$task_directory/distribution/INSTALL.txt" <<'EOF'
This development artifact is ad-hoc signed, not Developer ID signed or notarized.
Downloaded copies may be blocked by Gatekeeper. Only open software whose source
you trust. After an attempted launch, macOS may offer Open Anyway under System
Settings > Privacy & Security. Use that supported approval workflow if available;
do not disable Gatekeeper globally. Building locally is another option.
EOF
fi
ditto -c -k --sequesterRsrc "$task_directory/distribution" "$task_directory/output/$archive_name"
if [[ "$eave_dmg" == true ]]; then
    ditto "$task_directory/distribution" "$task_directory/disk-image"
    ln -s /Applications "$task_directory/disk-image/Applications"
    image_path="$task_directory/output/Eave-v$eave_version.dmg"
    hdiutil create -volname "Eave $eave_version" -srcfolder "$task_directory/disk-image" -format UDZO -fs HFS+ "$image_path"
    if [[ "$eave_signed" == true ]]; then
        codesign --sign "$SIGNING_IDENTITY" --timestamp "$image_path"
        eave_notarize "$image_path" "$task_directory/dmg-notary-result.json"
        xcrun stapler staple "$image_path"
        xcrun stapler validate "$image_path"
        spctl --assess --type open --context context:primary-signature --verbose=2 "$image_path"
    fi
fi
(
    cd "$task_directory/output"
    if [[ "$eave_dmg" == true ]]; then shasum -a 256 "$archive_name" "Eave-v$eave_version.dmg" > SHA256SUMS.txt
    else shasum -a 256 "$archive_name" > SHA256SUMS.txt; fi
)

# Validate before replacing the previous generated release directory.
arguments=(--directory "$task_directory/output")
if [[ "$eave_signed" == true ]]; then arguments+=(--signed); fi
"$eave_root/Scripts/validate-artifacts.sh" "${arguments[@]}"
release_directory="$eave_root/dist/release"
[[ ! -L "$release_directory" ]] || eave_fail 'Refusing to replace a symlinked release directory.'
if [[ -e "$release_directory" ]]; then mv "$release_directory" "$task_directory/previous-release"; fi
if ! mv "$task_directory/output" "$release_directory"; then
    if [[ -e "$task_directory/previous-release" ]]; then mv "$task_directory/previous-release" "$release_directory"; fi
    eave_fail 'Could not install the generated release artifacts.'
fi
echo "Release artifacts: $release_directory"
if [[ "$eave_signed" == false ]]; then echo 'Development distribution: ad-hoc signed, not notarized. Downloaded copies may require macOS security approval.'; fi
