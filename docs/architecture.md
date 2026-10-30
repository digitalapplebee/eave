# Architecture

Eave is a Swift package with an AppKit/SwiftUI executable, an internal core module, and Swift Testing tests. It has no external package dependencies. Open `Package.swift` in Xcode; use the packaged `.app` for normal use and Login Items testing.

## Components

| Component | Responsibility |
| --- | --- |
| `Eave/App/` | MenuBarExtra, settings and About windows, application lifecycle, diagnostic entrypoints |
| `AppModel` | Observable UI state, preference persistence, appearance selection, render scheduling, ServiceManagement integration |
| `MenuBarAppearanceEngine` | MainActor coordination of displays, recovery records, accepted changes, confirmation and restoration |
| `WallpaperSource` | Classifies local still images, dynamic images, managed providers/posters and unknown sources |
| `WallpaperRenderer` | Actor-isolated ImageIO decoding, Core Graphics composition and generated-image caching |
| `AppKitWallpaperSystem` | Main-thread `NSWorkspace` wallpaper reads and writes |
| `DisplayManager` / `DisplayGeometry` | Per-display identity, backing size and menu-band geometry |
| `SystemEventMonitor` | Appearance, display, Space, activation and sleep/wake events |
| `WallpaperRecoveryService` | Durable original metadata, ownership checks and safe generated-file cleanup |

`WallpaperSystem` and `WallpaperRendering` are injectable protocols. Tests can delay rendering or simulate system failures without changing real desktop wallpapers.

## Rendering transaction

1. Read the latest settings, connected displays, wallpaper URL and options.
2. Resolve an existing Eave output back to its journaled original. Generated files never become new originals.
3. Require an identifiable local still image and supported layout options. Missing meaningful options are not replaced with guessed Fit or black fill values.
4. Render from the original on `WallpaperRenderer`'s actor executor.
5. Recheck the request revision, display geometry, source-file version and current wallpaper state.
6. Persist the original URL and archived options before calling `setDesktopImageURL`.
7. Submit the composed PNG, then compare the observed state with the expected result. Acceptance and confirmation are separate states.

The application never edits the original image, captures the desktop as a wallpaper source, covers native menu controls, or changes display resolution.

### Coordinates and placement

Screen measurements enter as local AppKit points. Canvas dimensions use the screen's backing scale. A single conversion maps the top-left menu-band rectangle into Quartz's bottom-left pixel coordinates; a secondary display's global origin never offsets its band.

`visibleFrame` is a work-area measurement, not an unconditional menu height. Its top inset is accepted only within bounds derived from the native status-bar thickness and safe area. Invalid geometry blocks application.

Image placement uses the original oriented image dimensions, independently of thumbnail decoding. Center mode accounts for image DPI before converting to backing pixels. Known Fill, Fit, Stretch and Center settings are reproduced; existing Fit/Center margins are preserved. AppKit ignores clipping for non-proportional modes, so an omitted clipping key is meaningful only for proportional scaling.

The renderer produces an opaque, 8-bit PNG, retaining the original RGB color space where available. Exact perceived colors still depend on macOS compositing and the display.

### Ordering and performance

Enable/disable and system events are scheduled immediately. Color and opacity changes use a 220 ms debounce to combine slider events. Cancellation and a revision number prevent an older result from applying after a newer request.

All system wallpaper mutations run on MainActor. Pending changes retain their target and known intermediate states, so a delayed getter does not trigger duplicate setters or confuse an earlier accepted Eave output with an external change. Disabling supersedes an accepted but unconfirmed enable.

Generated-image keys include the renderer version, original URL and file version, geometry, placement and color. Decoded images use an `NSCache` with a 128 MiB cost limit. Rendering working buffers can exceed that limit. There is no periodic polling or persistent render loop.

## Persistence and recovery

UI preferences live in UserDefaults under `eave.settings.v1`. With the default bundle identifier, recovery data lives in `~/Library/Application Support/com.eaveapp.Eave/`:

- `recovery.json`: display UUIDs, original file URLs, archived wallpaper options and generated URLs.
- `Generated/`: Eave's image copies and temporary render files.
- `instance.lock`: prevents simultaneous app/diagnostic processes from mutating the same state.

Journal writes are atomic and synchronized before application. Restoration requires that the visible wallpaper still belongs to the corresponding Eave record and that its original can be restored safely. Detected external URL or layout changes take precedence. The next launch can recover after an unexpected exit; there is no separate recovery daemon.

Old journals are read from their actual archived API options, rather than trusting previously guessed scalar fields. A legacy record pointing to a managed poster cannot restore the original provider configuration and is rejected instead of applying that poster.

Only unreferenced Eave PNG/tmp files older than a day are cleaned automatically. Referenced outputs remain available because hidden Spaces may still use them. Never remove the recovery directory before restoring affected desktops.

## Platform boundaries

`NSWorkspace` exposes image URLs and legacy layout options, not a complete provider configuration. Eave does not customize Golden Gate/Aerial, video, time-dependent or Light/Dark dynamic wallpapers. System-hosted images are conservatively treated as managed, including readable single-frame posters. Unknown third-party providers cannot always be identified reliably and are not a supported configuration.

Wallpaper reads and writes concern visible desktops. Display/Space events allow reconciliation when another desktop becomes visible, but there is no supported enumeration-and-restore operation for all Spaces. Full-screen windows can obscure the effect; menu auto-hide does not remove the wallpaper band. See the [validation record](rendering-validation.md) for verified behavior and the remaining manual checks.

The app contains no network requests, accounts, analytics or updater. Local logs include display geometry and identifiers; private error details and recovery paths should be reviewed before sharing a bug report.
