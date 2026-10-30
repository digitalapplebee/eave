# Rendering validation

This record separates observed defects, automated regression checks and unverified desktop behavior. Passing tests does not establish complete macOS compatibility.

## Confirmed causes

On macOS 27.0.1, existing recovery records and generated PNGs were inspected without changing the desktop. Three records identified `/System/Library/CoreServices/DefaultDesktop.heic` as the original. It is a symlink to `/System/Library/Wallpapers/.default/DefaultAerial.heic`; ImageIO reported one 4096×2160 frame.

The earlier classifier rejected some provider paths and multi-frame HEICs, but accepted this single-frame system poster as an ordinary still image. The user had selected Golden Gate. An image URL and three legacy options do not preserve that provider's full configuration, so composing or “restoring” the poster could replace the selected wallpaper.

Some journal records used `clips=false`. Missing options were also previously replaced with proportional Fit, no clipping and black fill. On a 3600×2338 canvas, fitting 4096×2160 yields an image about 1898 pixels high, leaving roughly 220 pixels above and below it. Stored PNGs contained **219 fully black rows at both edges**. With clipping enabled, the black preset had **80 black rows at the top and none at the bottom**. This confirms letterboxing as the source of the large bars; changing only a menu-height constant would not fix it.

The previous geometry calculation also accepted any upper `visibleFrame` exclusion as menu height. That was unsafe, although the observed 40-point inset on this display was valid and did not explain the 219-pixel bars.

Delayed getters and out-of-order render completion were separately tested as state-management risks. Their contribution to the reported incident was not directly observed.

## Implemented safeguards

- Classify sources as still, dynamic, managed or unknown. Only identifiable local still images with known applicable layout options are composited.
- Check both the original path and resolved symlink target. DefaultDesktop/DefaultAerial posters are excluded from rendering and legacy automatic restoration.
- Recover old layout data from the archived API dictionary, not previously guessed scalar fields.
- Use local AppKit points at input and backing pixels on the canvas, with one top-left-to-Quartz conversion. Validate `visibleFrame` against native status-bar and safe-area measurements.
- Place the original oriented image independently of thumbnail dimensions. Account for DPI in Center mode and retain the source RGB color space where possible.
- Require known clipping for proportional scaling. AppKit ignores clipping in Stretch/Center and can omit that key. An opaque, full-canvas Eave PNG does not depend on an unused system matte color for confirmation.
- Include the renderer version in cache keys. Never feed an Eave output back into rendering as its original.
- Apply enable/disable without debounce. Cancellation and revisions discard stale renders; setters are serialized on MainActor.
- Track accepted targets and known intermediate outputs separately from observed confirmation. A lagging getter does not submit the same change repeatedly or misclassify an earlier Eave output as an external choice.
- Supersede an unconfirmed enable when disabling. Roll back a partial write only over Eave's own attempted output. Restore an older Eave image after a render failure only when its still original is safe and no external change intervened.

## Source support

| Source | Behavior |
| --- | --- |
| Local still PNG/JPEG/TIFF/HEIF with known applicable options | Composition supported |
| Golden Gate and other Aerial/video providers | Detected managed sources are left untouched |
| Time-dependent or Light/Dark HEIC with dynamic metadata/multiple frames | Left untouched |
| System-hosted image, poster, Photos source or known provider/cache path | Conservatively left untouched, including single-frame posters |
| Unknown format, missing meaningful options or unknown layout keys | Rejected without guessed Fit/black values |
| Missing or unreadable image | Error without a wallpaper write |
| Legacy journal pointing to a poster rather than a provider configuration | Automatic poster restoration blocked; manual selection required |

**No dynamic wallpaper type is supported for customization.** If an older build already replaced Golden Gate, reselect it in Wallpaper settings. Its full provider configuration cannot be reconstructed from the old journal. Recovery data is retained rather than rewritten to guess an original.

An unknown third-party provider can expose a plausible local image and legacy options. Public APIs cannot reliably identify every such case; it is not a supported configuration. Use an explicitly selected local still image with rotation disabled.

## API boundary

[NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace) exposes image URLs, legacy options and an image setter. Its [allowClipping](https://developer.apple.com/documentation/appkit/nsworkspace/desktopimageoptionkey/allowclipping) option distinguishes Fit from Fill, but these APIs do not provide a complete provider configuration. Apple also [confirms the lack of an API for setting wallpaper on all Spaces](https://developer.apple.com/forums/thread/834630).

The SDK investigation did not identify a public mechanism that would safely customize Golden Gate while retaining its provider. Documented [window levels](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct) establish ordering, not a guarantee that native menu compositing samples a lower application window. An unverified overlay was therefore not introduced.

## Recorded verification

| Check | Result |
| --- | --- |
| Local environment | macOS 27.0.1, arm64, Xcode 27.1, Swift 6.4 |
| Debug/Release and packaged ad-hoc app | Built successfully |
| Automated regression suite | 33 tests in three suites passed; parameterized tests cover additional variants |
| Pixel tests | Top-only band, no added bottom band in Fill, explicit Fit fill, Retina DPI Center, EXIF orientation, original-file integrity, cache identity |
| Geometry tests | Retina/non-Retina, secondary-display origins, safe area, variable heights, hidden-menu fallback, invalid insets, coordinate conversion |
| State tests | Ten toggle intentions ending ON/OFF, stale colors, intermediate accepted outputs, delayed getter, repeated ON/OFF, restart, partial writes, render failures, external URL/layout changes, legacy records |
| Source tests | Still, multi-frame dynamic, single-frame managed/symlink, unknown, incomplete/unknown layout, missing and unreadable files |
| Real built-in display geometry | 1800×1169 points; 3600×2338 backing pixels; scale 2; safe top 38 points; visible top 40 points; band 80 pixels |
| Real managed-source preservation diagnostic | Ten toggle intentions, **zero write attempts**, unchanged observed URL/options, exit 0 |
| Legacy-output preservation diagnostic | Passed with `legacy-output=true`; zero write attempts; unchanged URL/options and recovery-journal SHA-256 |

The preservation diagnostic uses real AppKit snapshots and the same engine, but its adapter blocks every setter even if a regression attempts one. It verifies the refusal path, not the visual color effect or dynamic-wallpaper playback.

The API later reported an old Eave PNG whose journal original was DefaultDesktop. The new preflight refused to apply or restore that poster. Returning to the selected Golden Gate requires manual selection in System Settings.

## Manual validation

Close older Eave copies before rebuilding. Do not automatically replace the current managed wallpaper with a static test image: full restoration of its provider configuration is not guaranteed.

```sh
swift test
./Scripts/build-app.sh release
codesign --verify --strict dist/Eave.app
dist/Eave.app/Contents/MacOS/Eave --verify-preservation
open dist/Eave.app
```

### A — static wallpaper: visual acceptance pending

- [ ] Select a local PNG/JPEG manually and record its Fill/Fit/Stretch/Center setting.
- [ ] Enable once. Only the intended menu-band region changes; no new bottom or side margins appear.
- [ ] Check notch blending, text, system icons and native menu interactions.
- [ ] Disable once. The original wallpaper and layout return.
- [ ] Repeat for supported layouts and display scaling settings. Existing Fit/Center margins remain unchanged.
- [ ] With Eave closed, run `./Scripts/verify-desktop.sh`. Its API apply/restore result is not visual proof.

### B — Golden Gate and dynamic wallpapers

- [x] Verify managed system-poster classification and zero write attempts on a real Mac using `--verify-preservation`.
- [ ] Reselect Golden Gate manually if an older build already replaced it.
- [ ] Enable in the real popover. A concise unsupported-source message appears; wallpaper identity and dynamic behavior remain intact.
- [ ] Disable. Neither DefaultDesktop nor DefaultAerial is substituted.
- [ ] Repeat with Light/Dark and time-dependent HEIC wallpapers.

### C — rapid toggling

- [x] Automated tests: ten ON/OFF intentions with a delayed first render finish in the last requested state.
- [x] Automated tests: delayed getters and earlier accepted outputs do not cause duplicate submissions or false external-change errors.
- [ ] On a supported still wallpaper, click the real toggle ten times. The final ON/OFF state matches the last click, no oversized bars appear, and the original remains recoverable.

### Hardware and session checks: pending

- [ ] Visually check a notched MacBook display at different scaling settings.
- [ ] Test external Retina/non-Retina displays in different arrangements and during hot-plug.
- [ ] Test menu auto-hide and system menu-size changes.
- [ ] Test normal Spaces and full-screen apps. Visit all affected Spaces with Eave disabled before quitting.
- [ ] Test sleep/wake and lock/unlock.
- [ ] Change static/dynamic wallpapers while enabled; the external choice is preserved.
- [ ] Test macOS 26 at runtime.

A physical macOS 27 machine was available. Wallpaper, resolution, Space and sleep changes were not automated because preserving the current wallpaper and user session took priority. The unchecked scenarios remain unverified.

For log collection and recovery actions, see [Troubleshooting](troubleshooting.md). For code structure, see [Architecture](architecture.md).
