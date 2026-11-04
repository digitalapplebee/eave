# Troubleshooting

Start with the effect status near Eave's switch and the message in the popover or **Settings → Displays**. An enabled switch records the requested configuration; **Applied**, **Not applied**, partial results and restoration are reported separately. The style preview is not a desktop capture.

## No effect on Golden Gate or another dynamic wallpaper

On macOS 27, use the transparent-menu setup:

1. Choose **Menu Bar Settings** in Eave, or open **System Settings → Menu Bar**.
2. Turn **Show menu bar background** off. Keep **Accessibility → Display → Reduce Transparency** off.
3. Return to Eave and select **Background is off** to confirm the setup.

Eave then draws below the native menu without replacing the selected wallpaper. This path was visually checked with Golden Gate Automatic on a built-in macOS 27 display. Golden Gate is an abstract Dynamic Wallpaper, distinct from the Golden Gate Sunset aerial/video wallpaper.

The setup confirmation is manual. Eave has no public API for reading/changing that global background preference. If you later enable the system background, it can hide Eave's color; reset the confirmation in Eave's Settings and configure it again.

On macOS 26, or without confirmed transparent-menu setup, the wallpaper-composition fallback supports only suitable local still PNG/JPEG/TIFF/HEIF sources. It cannot preserve dynamic providers while replacing their image. A readable system poster is not treated as the selected wallpaper's configuration.

## Transparent-menu rendering pauses or does not appear

The transparent-menu path is suspended when the native menu is hidden/full-screen or system presentation settings disable transparency. Check the status rather than repeatedly toggling Eave. Return to a normal visible menu and recheck after the relevant system event.

Full-screen, auto-hide and multiple physical displays still require manual acceptance. Creating a panel alone is not proof that the system background allows its color to show.

## An older Eave build already changed Golden Gate

Reselect Golden Gate in **System Settings → Wallpaper**. Old recovery records may point to `DefaultDesktop.heic`, a system poster, instead of the original provider configuration. The current build deliberately refuses to apply that poster during restoration. It cannot reconstruct the missing dynamic configuration.

Keep the recovery folder until every affected desktop has been checked. Do not delete generated images to force the system to find another wallpaper.

## Black bars, the wrong height, or unexpected margins

Confirm that the current image is a supported local still image and inspect its Fill/Fit/Center setting. Existing Fit or Center margins are preserved; Eave should not introduce new margins when the original uses Fill.

The earlier black-band defect and measured evidence are documented in [Rendering validation](rendering-validation.md). If it recurs, include the display's logical resolution, backing scale, image dimensions, selected layout and Eave version in a report. Check the [manual validation checklist](rendering-validation.md#manual-validation) before calling a change verified.

## Black looks gray, or the text color differs from the preview

macOS controls menu translucency, tint and text color. Transparent-menu rendering does not recolor native glyphs: the development probe applied white while the native text stayed white, making it unreadable. Choose a contrasting background; black and dark colors work with the white glyphs in the verified Golden Gate dark-appearance scenario. Do not infer readability from the preview.

**Reduce Transparency** prevents this transparent-menu path and must be off. In wallpaper-composition mode it can also affect the final result. Eave provides a shortcut but does not change the setting automatically. Full-screen apps can obscure composition effects.

The preview inside Eave is an illustration of the selected style, not a capture or guarantee of the final system-composited color.

## “Waiting for macOS to confirm the wallpaper change”

The setter accepted a request, but the observed URL/layout has not yet confirmed it. Eave retains the pending target without repeatedly sending the same setter. Later activation, display, wake or Space events recheck it. Opening the popover also requests a check.

If the message persists, open Wallpaper settings and inspect the selected source. Eave does not force a fallback image to make the message disappear. A pending restoration can keep Eave open when Quit is requested.

## Eave paused after an external wallpaper change

In composition mode, Eave preserves a detected external URL/layout choice. Use **Retry** only when you want to apply composition to the now-selected, supported still wallpaper. Transparent-menu rendering does not replace an external wallpaper choice. Changes may be noticed at the next activation, display, wake or Space event; Eave does not continuously poll.

## Original wallpaper is missing, or Eave will not quit

Use **Settings → Open Recovery Folder** to inspect the saved original location. Reconnect the volume or restore the file to that location, then disable Eave again. Alternatively, choose the desired wallpaper manually in System Settings. A manual selection takes precedence over Eave's old output.

Quit is cancelled when safe restoration fails. Read the error instead of deleting the journal or forcing a different original. For a legacy managed-poster record, reselect the desired wallpaper manually as described above.

Only visible desktops can be restored at once. Disable Eave, visit each modified Space and reconnect affected displays before quitting or uninstalling.

## Recovery or preferences cannot be read

- A damaged recovery journal blocks wallpaper changes. Keep a copy for local inspection and restore the desired wallpapers manually through System Settings.
- Unreadable UI preferences fall back to a disabled configuration so the separate journal can still restore safe originals. Changing a setting saves fresh preferences.
- Recovery records contain local file paths and display identifiers. Do not attach an entire journal to a public issue without reviewing it.

## Launch at Login does not work

Run the packaged `.app` from a permanent location, normally `/Applications`, then enable **Launch at Login** in Eave's popover or Settings. If Eave shows an approval message, choose **Approve in Login Items…** and allow it in System Settings. Reopen Eave's popover to refresh the status. After moving the app or changing its signing identity, disable and enable Launch at Login again. ServiceManagement errors appear next to the switch.

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
