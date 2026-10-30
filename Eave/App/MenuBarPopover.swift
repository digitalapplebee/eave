import AppKit
import EaveCore
import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("eave").font(.system(size: 27, weight: .semibold, design: .rounded)).tracking(-1)
                    Text("Make your Mac yours.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enable Eave", isOn: $model.settings.enabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(!model.isReady).help("Apply or restore the menu bar wallpaper effect")
            }

            MenuBarPreview(style: model.effectiveStyle, enabled: model.settings.enabled)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Menu bar color").font(.headline)
                    Spacer()
                    Text(model.usesDarkColor ? "Dark appearance" : "Light appearance")
                        .font(.caption).foregroundStyle(.secondary)
                }
                AppearanceControls(model: model)
                Toggle(isOn: $model.settings.hideNotch) {
                    Label("Hide Notch", systemImage: "macbook.gen2")
                }.toggleStyle(.switch).controlSize(.small)
                Text("Hide Notch uses opaque black on every display.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!model.isReady)

            Divider()
            HStack {
                Text("Appearance").font(.subheadline)
                Spacer()
                Picker("Appearance", selection: $model.settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 150)
            }

            StatusView(model: model)

            Divider()
            HStack(spacing: 14) {
                Button { openWindow(id: "settings") } label: { Image(systemName: "gearshape") }
                    .help("Eave Settings").accessibilityLabel("Eave Settings")
                    .keyboardShortcut(",")
                Button("About Eave") { openWindow(id: "about") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 370)
    }
}

struct AppearanceControls: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(ColorPreset.allCases.filter { $0 != .custom }) { preset in
                    Button {
                        var selection = model.selection
                        selection.preset = preset
                        model.selection = selection
                    } label: {
                        Circle().fill(Color(nsColor: preset.color!.nsColor))
                            .frame(width: 31, height: 31)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1))
                            .overlay {
                                if model.selection.preset == preset {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(preset == .white || preset == .gray ? .black : .white)
                                }
                            }
                    }.buttonStyle(.plain).help(preset.rawValue)
                        .accessibilityLabel(preset.rawValue)
                        .accessibilityAddTraits(model.selection.preset == preset ? .isSelected : [])
                }
                Spacer(minLength: 0)
                ColorPicker("Custom", selection: Binding(get: {
                    Color(nsColor: model.selection.custom.nsColor)
                }, set: { color in
                    var selection = model.selection
                    selection.custom = RGBColor(NSColor(color))
                    selection.preset = .custom
                    model.selection = selection
                }), supportsOpacity: false)
                .labelsHidden().help("Choose a custom color")
                .accessibilityLabel("Custom menu bar color")
            }
            HStack {
                Text(model.selection.preset.rawValue).font(.caption)
                Spacer()
                if model.selection.preset != .custom {
                    Button("Use custom") {
                        var selection = model.selection
                        selection.preset = .custom
                        model.selection = selection
                    }.buttonStyle(.link).font(.caption)
                }
                Text(model.selection.color.hexString).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text("Opacity").font(.caption).foregroundStyle(.secondary)
                Slider(value: $model.settings.opacity, in: 0...1, step: 0.01) { Text("Menu bar opacity") }
                Text(model.settings.opacity, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
            }
        }.disabled(model.settings.hideNotch)
    }
}

struct MenuBarPreview: View {
    let style: BandStyle
    let enabled: Bool
    private var lightText: Bool { style.color.red * 0.2126 + style.color.green * 0.7152 + style.color.blue * 0.0722 < 0.55 }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                Text("Finder").fontWeight(.semibold)
                Text("File").opacity(0.7)
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text("9:41")
            }
            .font(.system(size: 9)).padding(.horizontal, 11).frame(height: 24)
            .foregroundStyle(enabled && lightText ? .white : .black)
            .background(enabled ? Color(nsColor: style.color.nsColor).opacity(style.opacity) : Color.white.opacity(0.4))
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                UnevenRoundedRectangle(topLeadingRadius: 70, topTrailingRadius: 20)
                    .fill(.primary.opacity(0.04)).rotationEffect(.degrees(-12)).offset(x: -45, y: 36)
                Text("Your desktop. A little more you.")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }.frame(height: 72)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Menu bar preview: \(enabled ? style.color.hexString : "disabled")")
    }
}

struct StatusView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            if model.isApplying {
                HStack { ProgressView().controlSize(.mini); Text("Updating desktop…") }
            } else if let failure = model.statuses.first(where: \.failed) {
                Label(failure.message, systemImage: "info.circle").foregroundStyle(.secondary)
                HStack {
                    Button("Wallpaper Settings") { model.openSystemSettings("com.apple.Wallpaper-Settings.extension") }
                    Spacer()
                    Button("Retry") { model.schedule(retry: true) }
                }.buttonStyle(.link)
            } else if let pending = model.statuses.first(where: \.pending) {
                Label(pending.message, systemImage: "clock").foregroundStyle(.secondary)
            } else {
                Label(model.settings.enabled && model.statuses.contains(where: \.applied) ? "Applied to the current desktop" : "Original wallpaper preserved",
                      systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
