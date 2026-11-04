<img src="docs/assets/app-icon.png" width="88" height="88" alt="Eave app icon">

# Eave

**Make your Mac yours.**

A minimal, open-source macOS utility for customizing your menu bar.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/digitalapplebee/eave/actions/workflows/ci.yml/badge.svg)](https://github.com/digitalapplebee/eave/actions/workflows/ci.yml)

Eave colors the background behind your real menu bar. On macOS 27, a confirmed transparent-menu setup can keep dynamic wallpapers intact; a separate still-wallpaper composition path is also available. Native menu controls stay in place. Eave runs from the menu bar, without a permanent Dock icon.

**Release status:** the source is public, and v0.1.0 is prepared locally. No downloadable GitHub release has been published yet. Check [Releases](https://github.com/digitalapplebee/eave/releases) for future installers, or build locally with the commands below. The [release checklist](docs/releasing.md) records the checks needed before distributing a binary release.

**Screenshots:** genuine UI and desktop-effect captures are still needed. The icon above is the actual app icon; no preview artwork is presented as a system screenshot. See the [capture guide](docs/screenshots/README.md).

## Features

- Black, Graphite, Dark Gray, Gray and White presets, plus a native custom color picker.
- Adjustable opacity; Hide Notch uses opaque black.
- Separate Light and Dark color profiles, with Follow System automation.
- A native SwiftUI popover with a live preview, Settings and About windows.
- Persistent preferences and Launch at Login through macOS Login Items.
- Transparent-menu rendering on macOS 27 without replacing the selected wallpaper.
- Per-display composition, display/Space/wake event handling and a recovery journal.
- No accounts, analytics, subscriptions, updater or application network requests.

**For Golden Gate or another dynamic wallpaper on macOS 27:** turn off **System Settings → Menu Bar → Show menu bar background**, then confirm **Background is off** in Eave. Eave adds a background window below the native menu without writing to the wallpaper provider. This does not add support for rewriting dynamic wallpaper files.

Without that confirmed setup, wallpaper composition requires a local still PNG, JPEG, TIFF or HEIF image with known placement options. Managed posters and unknown sources are not substituted for the selected wallpaper. macOS retains its native text color: choose a contrasting background. White text can become unreadable on a white band.

## Install without Xcode

Once the maintainer publishes a release:

1. Open [Releases](https://github.com/digitalapplebee/eave/releases) and read the version's compatibility and signing notes.
2. Download `Eave-v0.1.0.dmg` or `Eave-v0.1.0.zip`, along with `SHA256SUMS.txt` to verify the download.
3. Open the DMG and drag **Eave** to **Applications**, or extract the ZIP and move `Eave.app` there.
4. Open Eave from Applications, then click its icon in the macOS menu bar.
5. Enable customization and follow Eave's setup/status message. The first launch starts with the effect disabled.

The locally prepared v0.1.0 artifacts are **ad-hoc signed, not Developer ID signed or notarized**. Downloaded copies can be blocked by Gatekeeper. If you trust the source and macOS offers it after an attempted launch, use **System Settings → Privacy & Security → Open Anyway**, following [Apple's supported approval workflow](https://support.apple.com/en-us/102445). Do not disable Gatekeeper globally. A release is notarized only if its notes explicitly say so.

Place the downloaded assets and checksum manifest in the same folder, then run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

## Use Eave

Click the menu-bar icon and turn on **Enable Eave**. Choose a preset, open the custom color well, or adjust opacity. **Hide Notch** overrides the selected color with opaque black; it does not change resolution or move the native menu bar.

For transparent-menu rendering on macOS 27, choose **Menu Bar Settings**, turn off **Show menu bar background**, return to Eave and select **Background is off**. This is a manual confirmation; Eave does not change or read that global preference through an undocumented API. Keep **Reduce Transparency** off for this path. If you later re-enable the system background, reset the setup confirmation in Eave's Settings before configuring it again.

Choose **Follow System**, **Light** or **Dark**. In Settings, edit the separate color profiles. Enable **Launch at Login** directly in the menu-bar popover or in Settings to start Eave when you sign in. If macOS requires approval, choose **Approve in Login Items…**. Install Eave in its permanent location before registering it for login.

Turning Eave off removes its transparent-menu background windows. If wallpaper composition was used, it restores visible desktops: **visit every affected Space and reconnect affected displays while Eave is disabled before quitting**. Quit also tries to restore visible composed wallpapers; it keeps Eave open and explains restoration failures. If an older version recorded a system poster instead of the original Dynamic Wallpaper, select the wallpaper you want again in System Settings.

The header reports the actual effect state, including **Applied**, **Not applied**, partial application and restoration. The separate style preview represents the selected color; it is not a desktop capture or proof of application. Read the status for setup requirements, errors or pending confirmation.

## Compatibility

| Platform | Status |
| --- | --- |
| macOS 27.0.1, Apple Silicon | Local build/startup and preservation checks verified. Transparent-menu black/red backgrounds were observed on the built-in display after the system background was disabled. Other physical scenarios and static-composition visual acceptance remain pending. |
| macOS 26, Apple Silicon | Minimum deployment and hosted build/test target. Uses wallpaper composition; transparent-menu rendering is limited to macOS 27. Physical desktop behavior remains unverified. |
| macOS 25 or earlier | Unsupported by the deployment target. |
| Intel Macs | Not included in the current arm64 distribution. |

Multiple-display, hot-plug, sleep/wake and Space handling are implemented. Their physical acceptance checklist, along with auto-hide and full-screen behavior, is in [rendering validation](docs/rendering-validation.md). A successful build is not a claim that every desktop configuration works.

## Build from source

Requirements: an Apple Silicon Mac, macOS 26 or later, and a Swift 6.2-or-newer toolchain with a macOS 26 SDK. The locally verified environment is Xcode 27.1 / Swift 6.4 on macOS 27.0.1. [Hosted CI](https://github.com/digitalapplebee/eave/actions/workflows/ci.yml) selects Xcode 26.6 on the macOS 26 arm64 runner.

Clone the repository:

```sh
git clone https://github.com/digitalapplebee/eave.git
cd eave
```

Alternatively, use **Code → Download ZIP**, extract the source, and open its directory in Terminal.

```sh
swift build
swift test
./Scripts/build-app.sh debug
open dist/Eave.app
```

Open `Package.swift` directly in Xcode with **File → Open**, select the Eave scheme, and build. This is a Swift package; no generated `.xcodeproj` is needed. Use the packaged `.app` to test bundle metadata, its icon and Login Items. Quit Eave before replacing its bundle.

To test, build Release and create both installers:

```sh
./Scripts/release.sh --dmg
./Scripts/validate-artifacts.sh
```

Outputs:

```text
dist/Eave.app
dist/release/Eave-v0.1.0.zip
dist/release/Eave-v0.1.0.dmg
dist/release/SHA256SUMS.txt
```

Omit `--dmg` for ZIP-only packaging. These commands do not publish anything. See [releasing](docs/releasing.md) for versions, signing, notarization and GitHub preparation.

## How it works

With transparent-menu setup confirmed on macOS 27, Eave uses a narrow nonactivating `NSPanel` below the native menu's window level. It ignores mouse events, cannot become the key/main window, and follows the measured menu bounds. No wallpaper setter is used. Removing the panel restores the previous appearance, and macOS removes its windows when the process exits.

The composition fallback reads image URLs/options through `NSWorkspace` and renders independent still-image copies with ImageIO and Core Graphics. It journals originals before calling `setDesktopImageURL`, never edits an original file and never uses generated output as the next source. Existing Eave wallpaper copies must be safely restored before switching to transparent-menu rendering.

Rendering runs outside the UI actor, slider changes are combined, and stale work cannot replace newer settings. System events replace continuous polling. The journal supports recovery after a restart and avoids overwriting wallpaper changes made outside Eave.

Public APIs have limits:

- Dynamic providers are not rewritten or reconstructed. Transparent-menu rendering colors a separate window while leaving their configuration intact. The composition fallback still rejects dynamic files and system posters.
- The transparent-menu path pauses when the native menu is hidden/full-screen or when system presentation/transparency settings make it unavailable. Full-screen, auto-hide and multiple physical displays are not claimed as visually verified.
- macOS retains menu text/icon colors. A background can therefore have poor contrast even when the selected color is applied.
- Composition can immediately restore only visible desktops. Other Spaces/disconnected displays retain recovery records. Applying an image may turn off macOS **Show on all Spaces**.
- A composed wallpaper band remains when the menu bar auto-hides. Full-screen apps may obscure it.
- System appearance changes select Eave's saved profile; Eave does not change the system appearance itself.
- Scripted wallpaper changes are noticed on the next relevant event or manual check, not by a polling timer.

Details: [architecture](docs/architecture.md), [troubleshooting](docs/troubleshooting.md), and [validation evidence](docs/rendering-validation.md).

## Privacy

The application contains no analytics, account system, network client or automatic updater. It requests neither Screen Recording nor Accessibility access. Launch at Login uses `SMAppService` and may need system approval. Eave is a directly distributed, unsandboxed utility with an empty entitlement file; ordinary file APIs access wallpaper sources.

Preferences use UserDefaults key `eave.settings.v1`. With the default bundle ID, recovery metadata and generated copies are stored in:

```text
~/Library/Application Support/com.eaveapp.Eave/
```

The local journal contains wallpaper file URLs and display UUIDs. Unified Logging includes display identifiers and geometry at debug level; error text is private. Do not upload journals or unreviewed logs/screenshots to a public issue. See [SECURITY.md](SECURITY.md).

## Uninstall safely

1. Turn Eave off and confirm its background windows disappear. If composition was used, visit all affected Spaces and reconnect affected displays; confirm wallpaper restoration and resolve any error first.
2. Turn off **Launch at Login** in Eave or remove it from macOS Login Items.
3. Quit Eave, then move `Eave.app` from Applications to the Trash.
4. Optionally remove default-bundle preferences with `defaults delete com.eaveapp.Eave`. A custom bundle ID uses a different domain.
5. Only after every affected desktop has been restored, optionally move Eave's Application Support folder to the Trash in Finder. Keep it if any Space uses a generated wallpaper or needs recovery.

Never delete original wallpaper files. Removing the app alone does not restore unreachable Spaces or a dynamic-provider configuration lost by an older version.

## Community

Use [Issues](https://github.com/digitalapplebee/eave/issues) to report bugs or request features. See [CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), [SECURITY.md](SECURITY.md), and [CHANGELOG.md](CHANGELOG.md). Discussions is not enabled.

## License

[MIT](LICENSE), copyright © 2026 digitalapplebee. The [license inventory](docs/license-audit.md) records the source/dependency audit and separate terms for Apple resources and the Code of Conduct.
