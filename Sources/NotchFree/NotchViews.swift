import SwiftUI
import AppKit
import NotchFreeCore
import EventKit

private struct PanelReveal: ViewModifier {
    var progress: CGFloat
    func body(content: Content) -> some View {
        content.opacity(progress).blur(radius: (1 - progress) * 7)
            .scaleEffect(0.96 + progress * 0.04, anchor: .top)
    }
}

struct NotchShape: Shape {
    var radius: CGFloat = 28
    var animatableData: CGFloat { get { radius } set { radius = newValue } }
    func path(in rect: CGRect) -> Path {
        let shoulder: CGFloat = 12, r = min(radius, (rect.height - shoulder) / 2)
        let w = rect.width, h = rect.height
        return Path { p in
            p.move(to: .zero)
            p.addCurve(to: CGPoint(x: shoulder, y: shoulder), control1: CGPoint(x: shoulder, y: 0), control2: CGPoint(x: shoulder, y: 0))
            p.addLine(to: CGPoint(x: shoulder, y: h - r))
            p.addQuadCurve(to: CGPoint(x: shoulder + r, y: h), control: CGPoint(x: shoulder, y: h))
            p.addLine(to: CGPoint(x: w - shoulder - r, y: h))
            p.addQuadCurve(to: CGPoint(x: w - shoulder, y: h - r), control: CGPoint(x: w - shoulder, y: h))
            p.addLine(to: CGPoint(x: w - shoulder, y: shoulder))
            p.addCurve(to: CGPoint(x: w, y: 0), control1: CGPoint(x: w - shoulder, y: 0), control2: CGPoint(x: w - shoulder, y: 0))
            p.closeSubpath()
        }
    }
}

struct IconButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.75)).help(label).accessibilityLabel(label)
    }
}

struct AlbumArt: View {
    var data: Data?
    var size: CGFloat
    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.35, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                }
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

struct PlaybackBars: View {
    @Environment(\.nookAccent) private var nookAccent
    var playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !playing || reduced)) { timeline in
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<5) { index in
                    let phase = timeline.date.timeIntervalSinceReferenceDate * (3 + Double(index) * 0.4)
                    Capsule().fill(nookAccent).frame(width: 2.5, height: playing ? 5 + CGFloat((sin(phase) + 1) * 6) : 4)
                }
            }.frame(width: 25, height: 24)
        }.accessibilityLabel(playing ? "Playing" : "Paused")
    }
}

struct NotchRootView: View {
    @Environment(\.nookAccent) private var nookAccent
    @ObservedObject var model: AppModel
    @ObservedObject private var media: MediaProvider
    @ObservedObject private var shelf: ShelfStore
    let geometry: ScreenGeometry
    let availableWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduced
    init(model: AppModel, geometry: ScreenGeometry, availableWidth: CGFloat) {
        self.model = model; self.media = model.media; self.shelf = model.shelf
        self.geometry = geometry; self.availableWidth = availableWidth
    }
    var expanded: Bool { model.presentation.expanded }
    var activity: Activity? { model.presentation.visibleActivity }
    var size: PanelSize { model.panelSize(geometry: geometry, availableWidth: availableWidth - PanelMetrics.shadowGutter) }
    var width: CGFloat { size.width }
    var height: CGFloat { size.height }
    private var panelShape: NotchShape { NotchShape(radius: expanded ? 48 : 13) }
    var motion: Animation { reduced ? .easeOut(duration: 0.12) : .spring(response: expanded ? 0.4 : 0.3, dampingFraction: 0.82) }
    var body: some View {
        VStack(spacing: 0) {
            topStrip.frame(height: geometry.height)
            if expanded {
                expandedContent
                    .transition(reduced ? .opacity : .modifier(active: PanelReveal(progress: 0), identity: PanelReveal(progress: 1)))
                    .padding(.horizontal, 28).padding(.bottom, PanelMetrics.bottomPadding)
            } else if let activity {
                HStack(spacing: 10) {
                    if let level = activity.level {
                        GeometryReader { reader in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.15))
                                Capsule().fill(nookAccent).frame(width: reader.size.width * min(1, max(0, level)))
                            }
                        }.frame(height: 5)
                        Text("\(Int(level * 100))%").monospacedDigit().font(.system(size: 11, weight: .semibold))
                    } else {
                        VStack(spacing: 2) {
                            Text(activity.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            if !activity.subtitle.isEmpty { Text(activity.subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 30).frame(height: 40).transition(.opacity)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .background { panelShape.fill(.black) }
        .overlay { panelShape.stroke(model.presentation.dragging ? nookAccent : .clear, lineWidth: 1.5) }
        .clipShape(panelShape)
        .shadow(color: .black.opacity(expanded ? 0.32 : 0.1), radius: expanded ? 18 : 5, y: 7)
        .animation(motion, value: expanded).animation(motion, value: width).animation(motion, value: height)
        .animation(.easeOut(duration: 0.2), value: model.presentation.tab)
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .frame(width: availableWidth, height: PanelMetrics.envelopeHeight(notchHeight: geometry.height), alignment: .top)
    }
    private var topStrip: some View {
        HStack(spacing: 0) {
            Group {
                if let activity { Image(systemName: activity.symbol).foregroundStyle(nookAccent).font(.system(size: 13, weight: .semibold)) }
                else if media.snapshot.available { AlbumArt(data: media.snapshot.artwork, size: 22) }
                else if model.library.timer.isRunning { Image(systemName: "timer").foregroundStyle(nookAccent) }
                else if !shelf.items.isEmpty { Image(systemName: "tray.fill").foregroundStyle(nookAccent) }
            }.frame(maxWidth: .infinity)
            Color.clear.frame(width: geometry.width - 20)
            Group {
                if media.snapshot.available { PlaybackBars(playing: media.snapshot.playing) }
                else if model.library.timer.isRunning { Text(timeString(model.library.timer.remaining(at: model.now))).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(nookAccent) }
                else if !shelf.items.isEmpty { Text("\(shelf.items.count)").font(.system(size: 11, weight: .semibold)) }
            }.frame(maxWidth: .infinity)
        }.padding(.horizontal, 20).contentShape(Rectangle())
            .onTapGesture { if expanded { model.close(force: true) } else { model.open() } }
            .accessibilityLabel("Toggle NotchFree")
    }
    private var expandedContent: some View {
        VStack(spacing: PanelMetrics.spacing) {
            HStack(spacing: 4) {
                tabButton("Home", symbol: "square.grid.2x2.fill", tab: .home)
                tabButton("Tray", symbol: "tray.fill", tab: .tray)
                if !shelf.items.isEmpty { Text("\(shelf.items.count)").font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
                if model.library.timer.isRunning { Text(timeString(model.library.timer.remaining(at: model.now))).font(.system(size: 11, design: .monospaced)).foregroundStyle(nookAccent) }
                IconButton(symbol: "gearshape", label: "Settings") { model.showSettings?() }
                IconButton(symbol: "chevron.up", label: "Close panel") { model.close(force: true) }
            }
            if let message = model.message {
                HStack { Text(message).font(.caption).lineLimit(2).help(message); Spacer(); Button("Dismiss") { model.message = nil }.buttonStyle(.plain) }
                    .foregroundStyle(.orange).frame(height: PanelMetrics.messageHeight)
            }
            if model.presentation.tab == .tray { TrayView(model: model, shelf: shelf).transition(.opacity) }
            else {
                Group {
                    if model.library.widgets.isEmpty {
                        VStack(spacing: 10) {
                            Text("Room for what matters.").font(.headline)
                            Button("Choose widgets") { model.showSettings?() }.buttonStyle(.bordered)
                        }.frame(maxWidth: .infinity)
                    } else if model.selectedWidget == .media && model.library.widgets.contains(.calendar) {
                        HStack(spacing: 22) {
                            MusicView(media: media, now: model.now).frame(maxWidth: .infinity)
                            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
                            CalendarView(provider: model.calendar).frame(maxWidth: .infinity)
                        }
                    } else { widget }
                }.frame(height: PanelMetrics.widgetHeight)
                HStack(spacing: 4) {
                    ForEach(model.library.widgets) { kind in
                        Button { model.selectWidget(kind) } label: {
                            Image(systemName: widgetSymbol(kind)).font(.system(size: 13)).frame(width: 34, height: 28)
                                .foregroundStyle(model.selectedWidget == kind ? nookAccent : .white.opacity(0.4))
                                .background(model.selectedWidget == kind ? nookAccent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).help(kind.title).accessibilityLabel(kind.title)
                    }
                    Spacer()
                    Text("A little more space.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.25))
                }.padding(.horizontal, PanelMetrics.footerHorizontalPadding)
            }
        }
    }
    private func tabButton(_ title: String, symbol: String, tab: PanelTab) -> some View {
        Button { model.presentation.editing = false; model.camera.stop(); model.open(tab) } label: {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(model.presentation.tab == tab ? Color.white.opacity(0.1) : .clear, in: Capsule())
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(model.presentation.tab == tab ? .white : .white.opacity(0.45))
    }
    @ViewBuilder private var widget: some View {
        switch model.selectedWidget {
        case .media: MusicView(media: media, now: model.now)
        case .calendar: CalendarView(provider: model.calendar)
        case .timer: TimerWidget(model: model)
        case .notes: NotesWidget(model: model)
        case .tasks: TasksWidget(model: model)
        case .shortcuts: ShortcutsWidget(provider: model.shortcuts)
        case .mirror: MirrorWidget(camera: model.camera)
        }
    }
}

func widgetSymbol(_ kind: WidgetKind) -> String {
    switch kind { case .media: return "music.note"; case .calendar: return "calendar"; case .timer: return "timer"; case .notes: return "note.text"; case .tasks: return "checklist"; case .shortcuts: return "square.stack.3d.up"; case .mirror: return "person.crop.circle" }
}
func timeString(_ seconds: Double) -> String { let value = Int(max(0, seconds).rounded(.up)); return String(format: "%02d:%02d", value / 60, value % 60) }

struct MusicView: View {
    @Environment(\.nookAccent) private var nookAccent
    @ObservedObject var media: MediaProvider
    var now: Date
    @State private var seeking: Double = 0
    @State private var isSeeking = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if media.snapshot.available {
                HStack(spacing: 14) {
                    AlbumArt(data: media.snapshot.artwork, size: 78).id(media.snapshot.identity).transition(.opacity)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(media.snapshot.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                        Text(media.snapshot.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        HStack(spacing: 10) {
                            IconButton(symbol: "backward.end.fill", label: "Previous track") { media.send(5) }
                            IconButton(symbol: media.snapshot.playing ? "pause.fill" : "play.fill", label: media.snapshot.playing ? "Pause" : "Play") { media.send(2) }
                            IconButton(symbol: "forward.end.fill", label: "Next track") { media.send(4) }
                        }.padding(.leading, -8)
                    }
                }
                if media.snapshot.duration > 0 {
                    VStack(spacing: 1) {
                        Slider(value: Binding(get: { isSeeking ? seeking : media.snapshot.position(at: now) }, set: { seeking = $0 }), in: 0...max(1, media.snapshot.duration), onEditingChanged: { editing in
                            isSeeking = editing; if !editing { media.seek(seeking) }
                        }).tint(nookAccent).controlSize(.mini).accessibilityLabel("Playback position")
                        HStack { Text(timeString(isSeeking ? seeking : media.snapshot.position(at: now))); Spacer(); Text(timeString(media.snapshot.duration)) }
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
                    }
                }
            } else {
                HStack(spacing: 14) {
                    AlbumArt(data: nil, size: 66)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your next soundtrack.").font(.system(size: 14, weight: .medium))
                        Text("Play something in your favorite app.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Text(media.status).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).animation(.easeOut(duration: 0.2), value: media.snapshot.identity)
    }
}

struct CalendarView: View {
    @Environment(\.nookAccent) private var nookAccent
    @ObservedObject var provider: CalendarProvider
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { provider.selectedDay = Date(); provider.refresh() } label: { Text(AppEnglish.month(provider.selectedDay)).font(.system(size: 23, weight: .semibold, design: .rounded)).contentShape(Rectangle()) }.buttonStyle(.plain)
                Spacer()
                IconButton(symbol: "chevron.left", label: "Previous week") { shift(-7) }
                IconButton(symbol: "chevron.right", label: "Next week") { shift(7) }
            }
            HStack(spacing: 3) {
                ForEach(-3...3, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: provider.selectedDay)!
                    Button { provider.selectedDay = date; provider.refresh() } label: {
                        VStack(spacing: 3) {
                            Text(AppEnglish.weekday(date)).font(.system(size: 8)).foregroundStyle(.secondary)
                            Text(AppEnglish.day(date)).font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(offset == 0 ? Color.black : .white.opacity(0.6)).frame(width: 24, height: 24)
                                .background(offset == 0 ? nookAccent : .clear, in: Circle())
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            if !provider.access { Button("Connect calendar") { provider.requestAccess() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(nookAccent) }
            else if provider.events.isEmpty { Text(provider.status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.35)) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(provider.events, id: \.eventIdentifier) { event in
                            Button { NSWorkspace.shared.open(URL(string: "ical://")!) } label: {
                                HStack(spacing: 6) {
                                    Capsule().fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3, height: 22)
                                    Text(event.title ?? "Event").lineLimit(1)
                                    Spacer(minLength: 2)
                                    if event.isAllDay { Text("All day") } else { Text(AppEnglish.time(event.startDate)) }
                                }.font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 48)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func shift(_ days: Int) { provider.selectedDay = Calendar.current.date(byAdding: .day, value: days, to: provider.selectedDay)!; provider.refresh() }
}
