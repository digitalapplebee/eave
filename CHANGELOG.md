# Changelog

Notable changes are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Transparent-menu coloring on macOS 27 after manually confirming that the system menu-bar background is off; dynamic wallpaper providers stay selected.
- Launch at Login control in the menu-bar popover, with system approval guidance and registration errors beside the switch.

### Fixed

- Hide the transparent-menu background in Mission Control so it does not cover Spaces controls.
- Show the observed effect/restoration state separately from the enable request and selected-style preview.
- Mark scheduled appearance updates pending before debounce, and remove the duplicate opacity-slider label.
- Refresh Login Items status when opening its controls and after registration failures.

## [0.1.0] — Prepared, not published

### Added

- Native SwiftUI menu bar interface, desktop preview, settings, and About window.
- Black, Graphite, Dark Gray, Gray, White, custom colors, and opacity controls.
- Hide Notch mode using an opaque black wallpaper band.
- Separate Light/Dark colors, Follow System, persistent preferences, and Launch at Login integration.
- Static-wallpaper composition with per-display geometry and a recovery journal.
- Display, wake, Space, and appearance event handling.
- Automated tests and desktop-preservation diagnostics.
- Source-build, packaging, checksum, and artifact-validation scripts.
- CI/release preparation workflows and contributor documentation.

### Fixed

- Guessed Fit/black defaults that could introduce large top and bottom wallpaper bars.
- Single-frame system posters being treated as a user's recoverable static wallpaper.
- Unbounded `visibleFrame` geometry and placement based on decoded thumbnail dimensions.
- Stale rendering and delayed wallpaper getter state during rapid setting changes.

### Limitations

- Dynamic wallpaper files are not rewritten. Transparent-menu coloring requires macOS 27, explicit setup and a contrasting background because macOS retains its menu text color.
- macOS controls the final menu bar translucency and text colors.
- Automatic restoration is limited to visible desktops; other Spaces must be visited before quitting.
- Local macOS 27 build/unit-test and preservation checks do not establish complete visual compatibility. The manual checklist remains part of release approval.
- No public release, Developer ID notarization, or hosted CI result is claimed by this entry.
