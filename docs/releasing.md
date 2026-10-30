# Preparing a release

The initial version is **0.1.0**, build **1**, from `Resources/Info.plist`. The source repository is [digitalapplebee/eave](https://github.com/digitalapplebee/eave). A binary release is prepared locally but has not been published. No commands below publish a GitHub release unless a maintainer separately approves that action.

## Local builds and installers

Quit Eave before replacing its bundle. Run from the project root:

```sh
./Scripts/build-app.sh debug
./Scripts/build-app.sh release
./Scripts/package.sh --dmg
./Scripts/validate-artifacts.sh
```

For the full test/build/package sequence:

```sh
./Scripts/release.sh --dmg
```

Outputs:

```text
dist/Eave.app
dist/release/Eave-v0.1.0.zip
dist/release/Eave-v0.1.0.dmg
dist/release/SHA256SUMS.txt
```

Omit `--dmg` for ZIP-only packaging. Archives contain the compiled arm64 app, the MIT license and English installation instructions. The DMG includes an Applications shortcut. Validation checks versions, the agent flag, architecture, signatures, ZIP contents, checksums and, when present, the mounted read-only DMG.

Scripts stage output before replacing generated artifacts and refuse symlinked output destinations. Release bundles have development debug maps stripped before signing, and distribution validation rejects an unstripped Debug app. They do not launch Eave, change wallpapers or upload artifacts. Build products are ignored by Git.

`BUNDLE_ID` can override the local default `com.eaveapp.Eave`. Use the same value for build, packaging and validation. A different identifier has separate preferences and recovery data: restore the old copy's affected desktops before switching identifiers.

## Local verification — October 30, 2026

| Check | Result |
| --- | --- |
| Automated tests | 33 tests passed on macOS 27.0.1 / Xcode 27.1 / Swift 6.4. |
| Release app and installers | arm64 app, ZIP, DMG, signatures, mounted image and SHA-256 manifest validated. |
| Packaging edge cases | Paths containing spaces passed; tampered ZIP, version mismatch, unstripped debug maps and missing signing credentials were rejected. |
| Source hygiene | No detected credentials or private keys; build/recovery/signing data ignored. Final release executable contained no development-home paths. |
| Preservation smoke check | Ten toggle intents, zero wallpaper-write attempts, current URL/options unchanged. |
| Documentation | Relative links and English-language checks passed; external documentation links and the MIT badge responded successfully. |
| GitHub-hosted CI | YAML, embedded shell and pinned actions reviewed; see the [CI workflow](https://github.com/digitalapplebee/eave/actions/workflows/ci.yml) for current execution results. |
| Developer ID / notarization | Not performed; no credentials were provided. |
| Screenshots / desktop visuals | Genuine captures and the remaining physical acceptance checklist are pending. |

## Version numbers

Before preparing a version, update these values in `Resources/Info.plist`:

```sh
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.0' Resources/Info.plist
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1' Resources/Info.plist
```

Use a numeric `major.minor.patch` version and a positive, increasing build number. Update `CHANGELOG.md` with actual changes. Keep the initial entry marked as prepared/unpublished until publication, then add the actual release date.

`EXPECTED_VERSION=v0.1.0` makes the scripts reject a plist/tag mismatch. Tags must match the plist version exactly. Do not create or push a release tag until the maintainer approves the reviewed source.

## Mode A: ad-hoc development distribution

Default builds use `codesign --sign -`. No paid Apple Developer account or notarization credentials are needed. An ad-hoc signature checks bundle integrity; it does not identify a Developer ID publisher or provide an Apple notarization ticket.

Downloaded copies may be blocked by Gatekeeper. State this in release notes. Direct users to [Apple's supported per-app approval workflow](https://support.apple.com/en-us/102445). Do not tell users to disable Gatekeeper globally or remove quarantine recursively.

## Mode B: Developer ID and notarization

This requires Apple Developer Program membership, a valid **Developer ID Application** certificate/private key in a keychain, and valid notarization credentials. No certificate, password, API key or profile belongs in the repository. This path has not been executed during local preparation because credentials were not provided.

Store credentials using `xcrun notarytool store-credentials` and a keychain profile. See [Apple's notarization workflow](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution). With an existing valid certificate and profile:

```sh
export SIGNING_IDENTITY='Developer ID Application: Your verified certificate name'
export NOTARY_PROFILE=EaveNotary
EXPECTED_VERSION=v0.1.0 ./Scripts/release.sh --signed --dmg
```

Replace the certificate description with the exact identity from `security find-identity -v -p codesigning`. Set `NOTARY_KEYCHAIN` as well when the profile is in a dedicated keychain.

Signed mode never falls back to ad-hoc. It signs with Hardened Runtime and a secure timestamp, submits an app ZIP with `notarytool --wait`, requires **Accepted**, staples and validates the ticket, and performs a Gatekeeper assessment. A requested DMG is signed, notarized, stapled and assessed separately. The final ZIP contains the stapled app.

```sh
./Scripts/validate-artifacts.sh --signed
```

A successful signing command alone is not proof of notarization. Do not describe an artifact as notarized until the whole signed path passes.

## GitHub configuration

The public source repository is configured at `https://github.com/digitalapplebee/eave`. Publishing source does not publish the locally prepared installers. Before a binary release, review the following repository settings.

1. Keep the default branch as `main`, review `.gitignore` and the [license inventory](license-audit.md), and inspect what will be committed. Exclude build products, wallpaper data and signing credentials.
2. Keep the README's Releases/Issues links and live CI badge in sync if the repository moves. Add Discussions only if enabled.
3. Enable Actions and run CI on a reviewed commit. Require its build/test job for pull requests if branch protection is available. Hosted macOS 26 checks are a baseline, not macOS 27 visual acceptance.
4. Keep private vulnerability reporting enabled, check notification settings, and designate a real private conduct-reporting contact, as described in [SECURITY.md](../SECURITY.md) and [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md).
5. Configure the `apple-release` and `release-review` environments with required reviewers before using signed builds or draft creation. Never expose signing secrets to pull-request jobs.

The signed `apple-release` environment requires:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID Application certificate and private key in a password-protected P12 |
| `MACOS_CERTIFICATE_PASSWORD` | P12 password |
| `MACOS_SIGNING_IDENTITY` | Exact Developer ID Application certificate identity |
| `APPLE_NOTARY_KEY_P8_BASE64` | Base64-encoded App Store Connect API private key for notarization |
| `APPLE_NOTARY_KEY_ID` | API key identifier |
| `APPLE_NOTARY_ISSUER_ID` | API issuer identifier |

The workflow imports credentials into a temporary keychain and removes temporary material even when a step fails. The default ad-hoc workflow does not need these secrets. Review the actual [release workflow](../.github/workflows/release.yml) before dispatching it.

## Release procedure

1. Complete [manual rendering validation](rendering-validation.md) and review [genuine screenshots](screenshots/README.md). Check the built installer's signing status and installation/uninstallation on a clean account or another Mac.
2. With explicit approval, create and push the matching tag, for example `v0.1.0`, from the reviewed commit. The tag workflow builds, tests and packages **Actions artifacts only**; it does not publish a GitHub release.
3. Inspect the build logs, versioned ZIP/DMG, checksums, `INSTALL.txt` and release notes. Confirm that the tag, plist and changelog agree.
4. If an approved draft is wanted, manually dispatch **Prepare release** with the existing tag, `create_draft=true` and `manual_validation_complete=true`. Select `signed=true` only when the protected signing environment and valid credentials are ready. The `release-review` environment gates draft creation.
5. Review the draft and attached assets. **Publishing it is a separate maintainer action requiring explicit approval.** The workflow has no public-publish step.

Review the actual GitHub workflow result for the release commit. Do not turn a local build result into a green hosted-CI claim.

## Public-release checklist

- [x] Repository URL, Releases/Issues links and real CI badge configured.
- [ ] Hosted CI passes on the release commit; runner/toolchain versions recorded.
- [ ] Static-desktop scenarios A/C and managed-wallpaper scenario B reviewed on real macOS.
- [ ] Genuine screenshots captured and checked for personal information.
- [ ] Version/build/changelog/tag agree; the release date reflects actual publication.
- [ ] Install/uninstall tested on a clean account or another Mac.
- [ ] Signing status stated accurately; signed artifacts pass notarization/stapling/Gatekeeper checks.
- [ ] Private vulnerability and conduct reporting configured.
- [ ] Final assets and checksums reviewed; public publication explicitly approved.

Homebrew Cask, automatic updates, an update feed, a website and Intel builds are not part of this release. They are optional future work, not dependencies of the current installers.
