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
                Text("Eave places a color band in a separate copy of your still wallpaper. Your menu bar stays native and interactive. Its text color and translucency remain controlled by macOS.")
                Text("Dynamic, video and detected managed wallpapers are left untouched. For the closest black match, check Reduce Transparency in Accessibility → Display. Exact displayed colors are not guaranteed.")
                Button("Accessibility Display Settings…") { model.openSystemSettings("com.apple.preference.universalaccess?Seeing_Display") }
                Text("Only visible desktops can be restored. When disabling Eave, visit each Space with an Eave wallpaper before quitting. Full-screen apps may obscure the effect. Applying a wallpaper may turn off macOS ‘Show on all Spaces’.")
                Text("With menu bar auto-hide, the wallpaper band remains visible. Eave follows display, wake, Space and application activation events; wallpaper changes made by scripts are detected at the next such event.")
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
