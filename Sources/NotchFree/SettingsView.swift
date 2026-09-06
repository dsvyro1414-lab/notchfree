import SwiftUI
import AppKit
import NotchFreeCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var page = "Welcome"
    @AppStorage("openOnHover") private var hover = true
    @AppStorage("gestures") private var gestures = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("allScreens") private var allScreens = false
    @AppStorage("screenID") private var screenID = 0
    @AppStorage("hideFullscreen") private var hideFullscreen = true
    @AppStorage("activities") private var activities = true
    @AppStorage("panelWidth") private var width = 720.0
    let pages = ["Welcome", "Appearance", "Media", "Widgets", "System", "About"]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Image(systemName: "rectangle.topthird.inset.filled").font(.system(size: 24)).foregroundStyle(nookAccent)
                    Text("NotchFree").font(.system(size: 17, weight: .semibold, design: .rounded))
                }.padding(.vertical, 24).padding(.horizontal, 12)
                ForEach(pages, id: \.self) { item in
                    Button { page = item } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon(item)).frame(width: 18)
                            Text(item); Spacer()
                        }.font(.system(size: 12, weight: page == item ? .semibold : .regular))
                            .padding(10).background(page == item ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(page == item ? .white : .white.opacity(0.5))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("YOUR MAC. A LITTLE MORE.").font(.system(size: 8, weight: .medium)).tracking(1.4).foregroundStyle(.white.opacity(0.25)).padding(12)
            }.padding(.horizontal, 12).frame(width: 185).background(Color(white: 0.065))
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    if page != "Welcome" {
                        Text(page).font(.system(size: 28, weight: .semibold, design: .rounded))
                    }
                    content
                    if let message = model.message { Text(message).foregroundStyle(.orange).font(.callout).textSelection(.enabled) }
                }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Color(white: 0.085))
        }.frame(minWidth: 730, minHeight: 570).preferredColorScheme(.dark)
            .onChange(of: hover) { _, _ in model.settingsChanged() }
            .onChange(of: allScreens) { _, _ in model.settingsChanged() }
            .onChange(of: screenID) { _, _ in model.settingsChanged() }
            .onChange(of: width) { _, _ in model.settingsChanged() }
            .onChange(of: hideFullscreen) { _, _ in model.settingsChanged() }
    }
    @ViewBuilder var content: some View {
        switch page {
        case "Welcome": welcome
        case "Appearance":
            section("Make yourself at home") {
                Toggle("Open on hover", isOn: $hover)
                Toggle("Trackpad gestures on the top strip", isOn: $gestures)
                Toggle("Haptic feedback", isOn: $haptics)
                Toggle("Quiet in fullscreen", isOn: $hideFullscreen)
                Toggle("Show brief activity previews", isOn: $activities)
            }
            section("Displays") {
                Toggle("Show on every display", isOn: $allScreens)
                if !allScreens {
                    Picker("Display", selection: $screenID) {
                        Text("Automatic (built-in first)").tag(0)
                        ForEach(NSScreen.screens, id: \.displayID) { Text($0.localizedName).tag(Int($0.displayID)) }
                    }
                }
                HStack { Text("Panel width"); Spacer(); Text("\(Int(width)) pt").foregroundStyle(.secondary).monospacedDigit() }
                Slider(value: $width, in: 600...900, step: 10).tint(nookAccent)
            }
            Text("Swipe down to open, up to close. Swipe sideways on the closed strip to change tracks. Reduce Motion follows your macOS setting.").font(.callout).foregroundStyle(.secondary)
        case "Media": MediaSettings(provider: model.media)
        case "Widgets":
            section("Your widget dock") {
                ForEach(WidgetKind.allCases) { kind in
                    HStack {
                        Toggle(kind.title, isOn: Binding(get: { model.library.widgets.contains(kind) }, set: { enabled in
                            if enabled { model.library.widgets.append(kind) }
                            else { model.library.widgets.removeAll { $0 == kind }; if model.selectedWidget == kind { model.selectWidget(model.library.widgets.first ?? .media) } }
                        }))
                        Spacer()
                        if let index = model.library.widgets.firstIndex(of: kind) {
                            Button { if index > 0 { model.library.widgets.swapAt(index, index - 1) } } label: { Image(systemName: "arrow.left") }.disabled(index == 0).help("Move earlier")
                            Button { if index + 1 < model.library.widgets.count { model.library.widgets.swapAt(index, index + 1) } } label: { Image(systemName: "arrow.right") }.disabled(index + 1 == model.library.widgets.count).help("Move later")
                        }
                    }
                }
            }
            CalendarSettings(provider: model.calendar)
        case "System": SystemSettings(model: model, hud: model.hud, devices: model.devices)
        default:
            Text("Small space. Open possibilities.").font(.system(size: 20, weight: .medium, design: .rounded))
            Text("NotchFree 0.1.0 · Source alpha").foregroundStyle(nookAccent)
            Text("An independent, open-source notch companion inspired by NotchNook. Built with SwiftUI and AppKit. Your notes, tasks and tray stay on this Mac.").foregroundStyle(.secondary)
            section("Built in the open") {
                Text("Our code is MIT licensed. System-wide media uses MediaRemote Adapter by Jonas van den Berg and contributors (BSD 3-Clause). SF Symbols are provided by macOS.").font(.callout)
                Link("MediaRemote Adapter", destination: URL(string: "https://github.com/ungive/mediaremote-adapter")!)
                Button("Show local data") { NSWorkspace.shared.open(AppModel.dataRoot) }
            }
            Text("Installed from source with a local ad-hoc signature. No Developer ID or notarization. Rebuilding can require granting macOS permissions again.").font(.callout).foregroundStyle(.secondary)
        }
    }
    var welcome: some View {
        VStack(alignment: .leading, spacing: 23) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [Color(red: 0.20, green: 0.28, blue: 0.23), Color(white: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing))
                NotchShape(radius: 23).fill(.black).frame(width: 285, height: 108)
                HStack(spacing: 17) {
                    Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(nookAccent).frame(width: 57, height: 57).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("A little more space.").font(.system(size: 12, weight: .medium))
                        HStack(spacing: 22) { Image(systemName: "backward.end.fill"); Image(systemName: "play.fill"); Image(systemName: "forward.end.fill") }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                }.padding(.top, 30)
            }.frame(height: 157)
            VStack(alignment: .leading, spacing: 8) {
                Text("Meet your new\nfavorite corner.").font(.system(size: 35, weight: .semibold, design: .rounded)).tracking(-1)
                Text("Your music, your next meeting, that file you need.\nRight where you already look.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5)).lineSpacing(4)
            }
            HStack(spacing: 18) {
                Label("Local first", systemImage: "internaldrive")
                Label("Open source", systemImage: "curlybraces")
                Label("Always free", systemImage: "heart")
            }.font(.system(size: 10)).foregroundStyle(nookAccent)
            Button {
                UserDefaults.standard.set(true, forKey: "onboarded")
                NSApp.keyWindow?.close(); model.forcePanel?()
            } label: { HStack { Text("Make room"); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 13, weight: .semibold)).padding(14).foregroundStyle(.black).background(nookAccent, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
            Text("Hover over the top center of your display to open.\nConnect optional features whenever you’re ready.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3)).lineSpacing(3)
        }
    }
    func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
    func icon(_ item: String) -> String {
        ["Welcome": "sparkle", "Appearance": "rectangle.topthird.inset.filled", "Media": "music.note", "Widgets": "square.grid.2x2", "System": "slider.horizontal.3", "About": "info.circle"][item] ?? "circle"
    }
}

struct MediaSettings: View {
    @ObservedObject var provider: MediaProvider
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose your soundtrack.").font(.title3)
            Picker("Source", selection: $provider.source) { ForEach(MediaProvider.Source.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).onChange(of: provider.source) { _, _ in provider.start() }
            Text(provider.status).font(.callout).foregroundStyle(.secondary)
            Button("Reconnect") { provider.start() }
            Text("Now Playing follows the active system media session, including supported browser playback. Apple Music and Spotify modes use macOS Automation permissions. Browser support depends on the player publishing a Now Playing session.").font(.callout).foregroundStyle(.secondary)
        }
    }
}
struct CalendarSettings: View {
    @ObservedObject var provider: CalendarProvider
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendars").font(.headline)
            if !provider.access { Button("Connect Calendar") { provider.requestAccess() } }
            else {
                HStack {
                    Button("Select all") { provider.selectedIDs = Set(provider.calendars.map(\.calendarIdentifier)); provider.saveSelection() }
                    Button("Clear") { provider.selectedIDs = []; provider.saveSelection() }
                }
                ForEach(provider.calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(calendar.title, isOn: Binding(get: { !UserDefaults.standard.bool(forKey: "calendarSelectionConfigured") || provider.selectedIDs.contains(calendar.calendarIdentifier) }, set: { enabled in
                        if !UserDefaults.standard.bool(forKey: "calendarSelectionConfigured") { provider.selectedIDs = Set(provider.calendars.map(\.calendarIdentifier)) }
                        if enabled { provider.selectedIDs.insert(calendar.calendarIdentifier) } else { provider.selectedIDs.remove(calendar.calendarIdentifier) }; provider.saveSelection()
                    }))
                }
                Toggle("Include all-day events", isOn: $provider.includeAllDay).onChange(of: provider.includeAllDay) { _, _ in provider.saveSelection() }
            }
        }.padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
}
struct SystemSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var hud: SystemHUDProvider
    @ObservedObject var devices: DeviceActivities
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle("Launch at login", isOn: Binding(get: { model.startup }, set: model.toggleStartup))
            Divider()
            Text("Volume & brightness").font(.headline)
            if hud.volumeSupported {
                HStack { Image(systemName: "speaker.wave.2"); Slider(value: Binding(get: { Double(hud.volume) }, set: { _ = hud.setVolume(Float($0)) }), in: 0...1).tint(nookAccent); Text("\(Int(hud.volume * 100))%").monospacedDigit().frame(width: 40) }
                Toggle("Mute", isOn: Binding(get: { hud.muted }, set: { _ = hud.setMute($0) }))
            } else { Text("The current audio output does not support software volume.").font(.callout).foregroundStyle(.secondary) }
            if let brightness = hud.brightness {
                HStack { Image(systemName: "sun.max"); Slider(value: Binding(get: { Double(hud.brightness ?? brightness) }, set: { _ = hud.setBrightness(Float($0)) }), in: 0...1).tint(nookAccent) }
            } else { Text("Brightness control is unavailable on this display.").font(.callout).foregroundStyle(.secondary) }
            Button(hud.keyboardEnabled ? "Use standard macOS indicators" : "Enable notch keyboard indicators") {
                if hud.keyboardEnabled { hud.disableKeyboard(); UserDefaults.standard.set(false, forKey: "replaceHUD") }
                else { hud.enableKeyboard(request: true) }
            }
            Text(hud.status).font(.callout).foregroundStyle(.secondary)
            Text("Accessibility is needed to replace keyboard indicators. Unsupported devices keep the normal macOS behavior. Brightness support uses a private system interface and may change with macOS updates.").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack { Text("Battery"); Spacer(); Text(devices.battery.map { "\($0)%\(devices.charging ? " · Plugged in" : "")" } ?? "No battery") }.font(.callout)
            Toggle("Bluetooth connection alerts", isOn: Binding(get: { devices.bluetoothEnabled }, set: { enabled in
                if enabled { devices.enableBluetooth() } else { devices.disableBluetooth() }; UserDefaults.standard.set(enabled, forKey: "bluetoothAlerts")
            }))
            Text(devices.bluetoothStatus).font(.caption).foregroundStyle(.secondary)
        }.onAppear { hud.refresh() }
    }
}
