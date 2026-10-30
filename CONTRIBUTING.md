# Contributing to Eave

Bug reports, documentation fixes, tests, and focused improvements are welcome. Read the [code of conduct](CODE_OF_CONDUCT.md) before participating.

## Set up a development environment

Use an Apple Silicon Mac running macOS 26 or later. The package requires Swift 6.2 or later and a macOS 26 SDK. Local development has been checked with Xcode 27.1 / Swift 6.4 on macOS 27.0.1; hosted CI selects Xcode 26.6 on the arm64 macOS 26 runner. A successful build does not verify every desktop configuration.

Clone `https://github.com/digitalapplebee/eave.git`, then open `Package.swift` in Xcode. There is no generated `.xcodeproj` to maintain.

```sh
swift build --arch arm64
swift test --arch arm64
./Scripts/build-app.sh debug
open dist/Eave.app
```

Quit a running development copy before replacing its bundle. Use the packaged `.app` when checking menu bar agent behavior or Launch at Login; `swift run` does not provide the complete bundle metadata.

## Project layout

- `Eave/App/`: SwiftUI interface, application lifecycle, and diagnostics.
- `Eave/Core/`: settings, geometry, image composition, system adapters, and recovery.
- `Tests/`: Swift Testing suites; system writes use test adapters.
- `Resources/`: bundle metadata, entitlements, and icon.
- `Scripts/`: build, packaging, validation, and diagnostic entrypoints.
- `docs/`: architecture, release instructions, and manual verification.

## Coding conventions

Prefer small changes over rewrites. Follow the existing four-space indentation and naming. Use Swift 6 concurrency checks, functional SwiftUI views, and `MainActor` for UI and AppKit wallpaper operations. Perform image decoding/composition outside the main actor. Reuse existing models, adapters, and controls before introducing abstractions or dependencies.

Preserve the real macOS menu bar. Do not edit original wallpaper files, render from an Eave-generated output, or replace an unsupported managed wallpaper with a still poster. Unknown configuration should produce an explanation and no wallpaper write. New rendering approaches need evidence from public APIs and real macOS testing.

Do not commit `.build`, `dist`, generated wallpapers, user-specific Xcode settings, environment files, certificates, or credentials. Do not copy third-party code without checking its license and preserving required notices.

## Report a bug or propose a feature

Use the repository's **Issues → New issue** forms after checking existing reports and [troubleshooting](docs/troubleshooting.md). Include the Eave/macOS version, Mac/display configuration, wallpaper type, reproduction steps, and expected/actual behavior. Redact logs and screenshots; do not upload your recovery journal or original wallpapers.

Explain the user problem before proposing a large change. An issue discussion is useful for architecture changes, dependencies, and features with macOS API limitations. It is not required for a typo or a small reproducible fix. Report vulnerabilities privately through [SECURITY.md](SECURITY.md).

## Pull requests

Create a focused branch such as `fix/wallpaper-layout` or `docs/install-guide`. Use short, descriptive commits such as `Fix layout validation for managed wallpapers`; a particular commit prefix is not required.

Open a pull request with the problem, resulting behavior, tests, and limitations. Complete the template and keep unrelated cleanup out of the diff. For visible UI changes, attach genuine screenshots without personal information. Maintainers may request a smaller scope or additional evidence before merging.

Run `swift test --arch arm64` and the relevant build before submitting. Add regression tests for meaningful behavior changes, particularly geometry, rendering, state transitions, and preservation. Pure documentation changes need link/command review rather than new tests.

For system integration changes, follow [manual rendering validation](docs/rendering-validation.md). Record which hardware, wallpaper types, Spaces, and macOS versions you actually checked. Unit tests do not prove live menu bar behavior. Never replace a contributor's managed wallpaper just to make a test pass.

Release preparation is documented in [docs/releasing.md](docs/releasing.md). Contributors should not publish tags, releases, or signing material as part of a normal pull request.
