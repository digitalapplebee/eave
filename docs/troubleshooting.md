# Troubleshooting

Start with the message in Eave's popover or **Settings → Displays**. An enabled switch records the requested configuration; it does not mean every display accepted the effect.

## No effect on Golden Gate or another dynamic wallpaper

This is intentional. Eave cannot preserve the full configuration of Aerial/video, time-dependent or Light/Dark dynamic providers while replacing their image. It leaves detected managed sources untouched and explains the limitation.

To use color customization, choose a local still PNG, JPEG, single-frame TIFF or HEIF image in Wallpaper settings, disable automatic rotation, then use **Retry**. A readable system poster is not treated as proof of a safely customizable wallpaper.

## An older Eave build already changed Golden Gate

Reselect Golden Gate in **System Settings → Wallpaper**. Old recovery records may point to `DefaultDesktop.heic`, a system poster, instead of the original provider configuration. The current build deliberately refuses to apply that poster during restoration. It cannot reconstruct the missing dynamic configuration.

Keep the recovery folder until every affected desktop has been checked. Do not delete generated images to force the system to find another wallpaper.

## Black bars, the wrong height, or unexpected margins

Confirm that the current image is a supported local still image and inspect its Fill/Fit/Center setting. Existing Fit or Center margins are preserved; Eave should not introduce new margins when the original uses Fill.

The earlier black-band defect and measured evidence are documented in [Rendering validation](rendering-validation.md). If it recurs, include the display's logical resolution, backing scale, image dimensions, selected layout and Eave version in a report. Check the [manual validation checklist](rendering-validation.md#manual-validation) before calling a change verified.

## Black looks gray, or the text color differs from the preview

macOS controls menu translucency, tint and text contrast. Eave changes the wallpaper underneath the menu, not those system settings. **Accessibility → Display → Reduce Transparency** may affect the result; Eave provides a shortcut but does not change it automatically. Full-screen apps can also cover the effect.

The preview inside Eave is an illustration of the selected style, not a capture or guarantee of the final system-composited color.

## “Waiting for macOS to confirm the wallpaper change”

The setter accepted a request, but the observed URL/layout has not yet confirmed it. Eave retains the pending target without repeatedly sending the same setter. Later activation, display, wake or Space events recheck it. Opening the popover also requests a check.

If the message persists, open Wallpaper settings and inspect the selected source. Eave does not force a fallback image to make the message disappear. A pending restoration can keep Eave open when Quit is requested.

## Eave paused after an external wallpaper change

When Eave detects a new URL or layout, it preserves the external choice. Use **Retry** only when you want to apply Eave to the now-selected, supported wallpaper. Changes made by scripts may be noticed at the next activation, display, wake or Space event; Eave does not continuously poll.

## Original wallpaper is missing, or Eave will not quit

Use **Settings → Open Recovery Folder** to inspect the saved original location. Reconnect the volume or restore the file to that location, then disable Eave again. Alternatively, choose the desired wallpaper manually in System Settings. A manual selection takes precedence over Eave's old output.

Quit is cancelled when safe restoration fails. Read the error instead of deleting the journal or forcing a different original. For a legacy managed-poster record, reselect the desired wallpaper manually as described above.

Only visible desktops can be restored at once. Disable Eave, visit each modified Space and reconnect affected displays before quitting or uninstalling.

## Recovery or preferences cannot be read

- A damaged recovery journal blocks wallpaper changes. Keep a copy for local inspection and restore the desired wallpapers manually through System Settings.
- Unreadable UI preferences fall back to a disabled configuration so the separate journal can still restore safe originals. Changing a setting saves fresh preferences.
- Recovery records contain local file paths and display identifiers. Do not attach an entire journal to a public issue without reviewing it.

## Launch at Login does not work

Run the packaged `.app` from a permanent location, normally `/Applications`. Check **System Settings → General → Login Items**, and approve Eave if the system requests it. After moving the app or changing its signing identity, disable and enable Launch at Login again. ServiceManagement errors are shown in Eave.

The executable started by `swift run` is not a substitute for an installed app bundle. Login after logout/reboot is a manual acceptance check.

## Downloaded application is blocked by macOS

See the [installation instructions](../README.md) for the difference between Developer ID notarized releases and ad-hoc development archives. Do not disable Gatekeeper globally. A valid ad-hoc signature is not notarization or an assurance that a downloaded build will open without a security warning.

## “Eave is already running”

Quit the existing instance before running another copy or a diagnostic command. The lock prevents competing render and restoration operations. Do not remove a live process's lock file.

## Collecting diagnostics

Run this in Terminal, reproduce the issue, then stop it with Control-C:

```sh
log stream --level debug --style compact --predicate 'subsystem == "com.eaveapp.Eave"'
```

Logs identify the request, display geometry, source category, scaling mode, cache use, application and restoration result. Error text uses private logging, but display UUIDs and dimensions are logged. Review all output before sharing it; remove personal paths, identifiers, notifications and private content from screenshots. See [CONTRIBUTING.md](../CONTRIBUTING.md) for reporting guidance.
