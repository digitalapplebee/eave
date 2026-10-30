# Genuine screenshots

No UI screenshots are committed yet. Captures require an interactive desktop and a supported still-wallpaper session. During release preparation, screen capture was available but automated interaction with the menu-bar popover was not authorized. The selected managed/legacy wallpaper was left intact. A preview illustration would not demonstrate a real menu-bar effect.

The README deliberately omits screenshot image links until real captures exist. The icon in `docs/assets/app-icon.png` is exported from Eave's actual app icon; it is not a UI screenshot.

## Capture checklist

Use the packaged application, not an unbundled `swift run` process. Set aside a clean desktop, hide private documents and notifications, and keep the same display scaling and appearance across the set. Do not include a user's name, email, file paths, recovery data or unrelated windows.

1. Build and launch:

   ```sh
   ./Scripts/build-app.sh release
   open dist/Eave.app
   ```

2. Click Eave's menu-bar icon. Use macOS **Shift–Command–4**, then **Space**, to capture the actual popover window. Save it as `main.png` in this directory. Keep text readable at its native resolution; a 2× Retina capture is suitable.
3. Open the native custom color picker and capture the genuine picker with enough of Eave visible to establish context. Save as `color-picker.png`. If a window capture cannot include both windows, use **Shift–Command–5 → Capture Selected Portion** and select only the relevant region.
4. For desktop-effect captures, manually choose a local still PNG/JPEG in Wallpaper settings. Do not use Golden Gate/Aerial or a system-managed wallpaper. Enable Eave with opaque black and verify that only the menu-bar band changes, the notch blends as expected, and no extra bottom band appears. Capture the clean top portion of that real desktop as `dark-menu-bar.png`.
5. Select another implemented preset, such as Graphite or Gray, verify the actual effect, and capture the same region as `customization.png`.
6. Disable Eave, visit every affected Space/display, and confirm restoration. Restore the wallpaper you want to keep.

| File | Required content | Publication status |
| --- | --- | --- |
| `main.png` | Real Eave popover | Awaiting manual capture |
| `color-picker.png` | Native picker connected to Eave | Awaiting manual capture |
| `dark-menu-bar.png` | Verified real black menu-bar effect | Awaiting supported-wallpaper capture |
| `customization.png` | Verified real additional color preset | Awaiting supported-wallpaper capture |

Inspect every PNG before committing it. Crop to the relevant UI or desktop region; do not paint over controls, replace wallpaper, combine a mock menu bar with a desktop, or imply that the live preview is a system screenshot. Keep pixel density and readable text consistent. Use lossless PNG optimization only; retain the original pixels and metadata required for correct color display.

After the files exist and have been reviewed, add relative image links to the README with captions that name the actual macOS version and distinguish the app's live preview from the real system-menu result. Do not add broken links in advance.
