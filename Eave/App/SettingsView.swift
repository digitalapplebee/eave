import AppKit
import EaveCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("Automation") {
                Picker("Appearance", selection: $model.settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("Eave remembers separate colors for Light and Dark. This controls Eave’s colors, not the appearance of other apps.")
                    .font(.caption).foregroundStyle(.secondary)
                ColorProfileRow(title: "Light", selection: $model.settings.light)
                ColorProfileRow(title: "Dark", selection: $model.settings.dark)
                Toggle("Launch at Login", isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLogin($0) }))
                if model.loginStatus == .requiresApproval {
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            if #available(macOS 27, *) {
                Section("Transparent menu bar") {
                    Text("To color dynamic wallpapers without replacing them, turn off ‘Show menu bar background’ in System Settings → Menu Bar, then confirm here. Eave does not change that system setting.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Menu Bar Settings…") { model.openSystemSettings("com.apple.ControlCenter-Settings.extension") }
                    if model.settings.transparentMenuBarConfirmed == true {
                        Text("Setup confirmed manually").foregroundStyle(.secondary)
                        Button("Reset setup confirmation") { model.settings.transparentMenuBarConfirmed = nil }
                    } else {
                        Button("Background is off") { model.settings.transparentMenuBarConfirmed = true }
                    }
                }
            }
            Section("Displays") {
                if model.statuses.isEmpty { Text("Enable Eave to check the current desktop.").foregroundStyle(.secondary) }
                ForEach(model.statuses) { status in
                    LabeledContent {
                        Text(status.message).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    } label: { Label(status.name, systemImage: "display") }
                }
                Button("Check Again") { model.schedule(retry: true) }
            }
            Section("How Eave works") {
                Text("With transparent-menu setup confirmed, Eave colors the area below your native menu without replacing the wallpaper. Otherwise, supported still wallpapers use a separate rendered copy.")
                Text("macOS keeps its menu text color. Choose a contrasting background; a white band can hide white text. Transparent-menu coloring also needs Reduce Transparency turned off.")
                Button("Accessibility Display Settings…") { model.openSystemSettings("com.apple.preference.universalaccess?Seeing_Display") }
                Text("Only visible desktops can be restored. When disabling Eave, visit each Space with an Eave wallpaper before quitting. Full-screen apps may obscure the effect. Applying a wallpaper may turn off macOS ‘Show on all Spaces’.")
                Text("Transparent-menu coloring pauses for auto-hide and full-screen presentation. Wallpaper-based bands remain part of the wallpaper. Eave follows display, wake, Space and application activation events.")
                Button("Open Recovery Folder") {
                    NSWorkspace.shared.open(WallpaperRecoveryService.defaultDirectory)
                }
            }.font(.caption)
            if model.errorMessage != nil {
                Section { StatusView(model: model) }
            }
        }
        .formStyle(.grouped).frame(width: 480, height: 650)
    }
}

private struct ColorProfileRow: View {
    let title: String
    @Binding var selection: ColorSelection
    var body: some View {
        HStack {
            Picker("\(title) color", selection: $selection.preset) {
                ForEach(ColorPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            if selection.preset == .custom {
                ColorPicker("\(title) custom color", selection: Binding(get: {
                    Color(nsColor: selection.custom.nsColor)
                }, set: { selection.custom = RGBColor(NSColor($0)) }), supportsOpacity: false).labelsHidden()
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "menubar.rectangle").font(.system(size: 36, weight: .light))
            Text("eave").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-1)
            Text("Make your Mac yours.").foregroundStyle(.secondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build")")
                .font(.caption).foregroundStyle(.secondary)
            Text("A native menu bar utility.\nOffline. No accounts. No analytics.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(width: 340)
    }
}
