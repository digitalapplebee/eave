# License and source inventory

Reviewed on October 29–30, 2026 for the prepared v0.1.0 release.

## Project license

Eave's original source and artwork are licensed under the [MIT License](../LICENSE). The project owner explicitly selected the public handle **digitalapplebee** for the copyright notice. The notice uses 2026, the year of this preparation.

The complete license follows the [Open Source Initiative's MIT text](https://opensource.org/license/mit).

## Inventory

| Item | Finding |
| --- | --- |
| Swift dependencies | `Package.swift` contains local targets only; no external packages or downloaded libraries. |
| Frameworks | AppKit, SwiftUI, Foundation, Core Graphics, ImageIO, CryptoKit, OSLog, UniformTypeIdentifiers, ServiceManagement and Swift Testing are supplied by Apple. Their frameworks are not bundled with Eave. |
| Vendored source | None found. No GPL headers, copied-source attributions or third-party implementation files were found in the inspected application/tests/scripts. |
| App icon | Original AppKit drawing in `Scripts/generate-icon.swift`; `Resources/Eave.icns` is generated from that source. No downloaded artwork or font files are bundled. |
| Interface symbols | SF Symbols are requested from macOS at runtime. Apple retains the rights to those symbols; Eave's MIT license does not relicense Apple resources. |
| Screenshots | Only genuine application captures may be added. No third-party wallpaper or stock art has been added for this preparation. |
| Code of Conduct | Its own attribution and reuse terms are included in [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md). |

No incompatible third-party code or required application-payload attribution was identified. A separate empty third-party-notices file has therefore not been added. Add the applicable license and notices before introducing any external code or asset.

## Scope and hygiene

The source inventory excludes generated `.build/` and `dist/` output. It found no API credentials, certificates, private keys, personal absolute paths or source files over 1 MB.

A separate binary audit found 29 development-home paths in the first packaged executable's Mach-O debug map. Release packaging now strips debug-map entries with `strip -S` before signing; distribution validation rejects unstripped maps. The final rebuilt executable contained zero development-home path occurrences. Global/undefined symbols and the executable UUID were preserved in the stripping check, and the rebuilt app passed its no-write preservation diagnostic. Debug builds retain their local debugging information.

This inventory was performed before the initial Git commit; there was no earlier repository history to audit. It records the observable source and assets, not ownership of undisclosed external material. The source repository is [digitalapplebee/eave](https://github.com/digitalapplebee/eave). Review future staged changes and keep build products, wallpaper copies, recovery journals and signing credentials out of Git.
