import SwiftUI
import AppKit
import NotchFreeCore

struct TimerWidget: View {
    @ObservedObject var model: AppModel
    @State private var minutes = 5
    var body: some View {
        HStack(spacing: 35) {
            VStack(alignment: .leading, spacing: 6) {
                Label("A moment of focus", systemImage: "timer").font(.system(size: 12)).foregroundStyle(nookAccent)
                Text(timeString(model.library.timer.remaining(at: model.now))).font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                Text(model.library.timer.completed ? "Time’s up. You earned a break." : model.library.timer.isRunning ? "One thing at a time." : "Make a little time for yourself.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 12) {
                if !model.library.timer.isRunning && model.library.timer.pausedRemaining == nil {
                    Picker("Minutes", selection: $minutes) { ForEach([1, 5, 10, 15, 25, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) } }.frame(width: 110)
                    Button("Start timer") { model.library.timer.start(seconds: Double(minutes * 60), now: Date()); model.feedback() }.buttonStyle(.borderedProminent).tint(nookAccent).foregroundStyle(.black)
                } else {
                    Button(model.library.timer.isRunning ? "Pause" : "Resume") {
                        if model.library.timer.isRunning { model.library.timer.pause(now: Date()) }
                        else { model.library.timer.resume(now: Date()) }
                    }.buttonStyle(.borderedProminent).tint(nookAccent).foregroundStyle(.black).disabled(model.library.timer.completed)
                    Button("Reset") { model.library.timer.reset() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal, 14)
    }
}

struct NotesWidget: View {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("A thought worth keeping", systemImage: "note.text").font(.system(size: 12)).foregroundStyle(nookAccent)
                Spacer()
                Text("Saved on this Mac").font(.system(size: 10)).foregroundStyle(.secondary)
                Button("Done") { focused = false; model.presentation.editing = false; model.saveNow() }.buttonStyle(.plain).font(.system(size: 11))
            }
            TextEditor(text: $model.library.note).font(.system(size: 13)).scrollContentBackground(.hidden).focused($focused)
                .padding(8).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    if model.library.note.isEmpty && !focused { Text("What’s on your mind?").font(.system(size: 13)).foregroundStyle(.white.opacity(0.25)).padding(13).allowsHitTesting(false) }
                }.accessibilityLabel("Quick note")
        }.onChange(of: focused) { _, value in model.presentation.editing = value }
            .onDisappear { model.presentation.editing = false; model.saveNow() }
    }
}

struct TasksWidget: View {
    @ObservedObject var model: AppModel
    @State private var draft = ""
    @State private var showArchive = false
    @FocusState private var focused: Bool
    var items: [Todo] { model.library.todos.filter { showArchive ? $0.completedAt != nil : $0.completedAt == nil }.sorted { $0.favorite && !$1.favorite } }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "plus").foregroundStyle(nookAccent)
                TextField("One small thing to do…", text: $draft).textFieldStyle(.plain).font(.system(size: 12)).focused($focused).onSubmit(add)
                Button("Add", action: add).buttonStyle(.plain).foregroundStyle(nookAccent).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(showArchive ? "Active" : "Completed") { showArchive.toggle(); focused = false }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(items) { todo in
                        HStack(spacing: 9) {
                            Button { update(todo) { $0.completedAt = todo.completedAt == nil ? Date() : nil } } label: { Image(systemName: todo.completedAt == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(nookAccent) }.buttonStyle(.plain).accessibilityLabel("Toggle completion")
                            Text(todo.text).font(.system(size: 12)).strikethrough(todo.completedAt != nil).lineLimit(2)
                            Spacer()
                            Button { update(todo) { $0.favorite.toggle() } } label: { Image(systemName: todo.favorite ? "star.fill" : "star").font(.system(size: 10)).foregroundStyle(todo.favorite ? nookAccent : .white.opacity(0.25)) }.buttonStyle(.plain).accessibilityLabel("Favorite task")
                        }.padding(.vertical, 3).contextMenu { Button("Delete task", role: .destructive) { model.library.todos.removeAll { $0.id == todo.id } } }
                    }
                    if items.isEmpty { Text(showArchive ? "Completed tasks will wait here." : "A clear list. A clear head.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 25) }
                }
            }
        }.onChange(of: focused) { _, value in model.presentation.editing = value }.onDisappear { model.presentation.editing = false }
    }
    func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        model.library.todos.append(Todo(text: text)); draft = ""; model.feedback()
    }
    func update(_ todo: Todo, action: (inout Todo) -> Void) {
        guard let index = model.library.todos.firstIndex(where: { $0.id == todo.id }) else { return }; action(&model.library.todos[index])
    }
}

struct ShortcutsWidget: View {
    @ObservedObject var model: AppModel
    @ObservedObject var provider: ShortcutProvider
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Label("Your shortcuts", systemImage: "square.stack.3d.up").foregroundStyle(nookAccent); Spacer(); IconButton(symbol: "arrow.clockwise", label: "Refresh shortcuts") { provider.refresh() } }.font(.system(size: 12))
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 8) {
                    ForEach(provider.names, id: \.self) { name in
                        Button { provider.run(name) } label: {
                            HStack { Image(systemName: provider.running == name ? "hourglass" : "bolt.fill").foregroundStyle(nookAccent); Text(name).lineLimit(1); Spacer() }
                                .font(.system(size: 11)).padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(provider.running != nil)
                    }
                }
                if !provider.status.isEmpty { Text(provider.status).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
    }
}

struct MirrorWidget: View {
    @ObservedObject var camera: CameraProvider
    var body: some View {
        HStack(spacing: 24) {
            Group {
                if camera.active { CameraPreview(session: camera.session) }
                else { Image(systemName: "person.crop.circle").font(.system(size: 46, weight: .ultraLight)).foregroundStyle(.white.opacity(0.3)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.05)) }
            }.frame(width: 228, height: 148).clipShape(RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 12) {
                Text("Looking good.").font(.system(size: 20, weight: .medium, design: .rounded))
                Text(camera.status).font(.system(size: 11)).foregroundStyle(.secondary)
                if !camera.devices.isEmpty {
                    Picker("Camera", selection: $camera.selectedID) { ForEach(camera.devices, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) } }
                        .labelsHidden().onChange(of: camera.selectedID) { _, _ in if camera.active { camera.stop(); camera.start() } }
                }
                Button(camera.active ? "Turn camera off" : "Open mirror") { if camera.active { camera.stop() } else { camera.start() } }.buttonStyle(.bordered)
            }
            Spacer()
        }.onDisappear { camera.stop() }
    }
}

struct TrayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shelf: ShelfStore
    @State private var selection = Set<UUID>()
    var selectedURLs: [URL] { shelf.items.filter { selection.contains($0.id) }.compactMap { shelf.url($0) } }
    var body: some View {
        VStack(spacing: 10) {
            if let error = shelf.error { Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2) }
            if shelf.items.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: model.presentation.dragging ? "tray.and.arrow.down.fill" : "tray").font(.system(size: 31, weight: .ultraLight)).foregroundStyle(nookAccent)
                    Text(model.presentation.dragging ? "Drop it here." : "A stop along the way.").font(.system(size: 17, weight: .medium, design: .rounded))
                    Text("Drop files here. Pick them up anywhere.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 143)
                    .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [4, 5])) }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85, maximum: 105))], spacing: 8) {
                        ForEach(shelf.items) { item in
                            if let url = shelf.url(item) {
                                FileDragTile(url: url, name: item.name, selected: selection.contains(item.id),
                                             urls: selection.contains(item.id) ? selectedURLs : [url],
                                             click: { event in
                                    if event.clickCount == 2 { NSWorkspace.shared.open(url) }
                                    else if event.modifierFlags.contains(.command) {
                                        if !selection.insert(item.id).inserted { selection.remove(item.id) }
                                    } else { selection = [item.id] }
                                }, dragging: { model.presentation.dragging = $0 })
                                    .frame(height: 94)
                                    .contextMenu {
                                        Button("Quick Look") { QuickLookController.shared.show([url]) }
                                        Button("Open") { NSWorkspace.shared.open(url) }
                                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                        Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([url as NSURL]) }
                                        Button("AirDrop") { model.airDrop([url]) }
                                        Divider()
                                        Button("Remove tray copy", role: .destructive) { shelf.remove(item) }
                                    }
                            }
                        }
                    }
                }.frame(height: 143)
            }
            HStack(spacing: 8) {
                IconButton(symbol: "plus", label: "Add files") {
                    let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
                    model.presentation.editing = true
                    panel.begin { result in
                        model.presentation.editing = false
                        if result == .OK { shelf.importFiles(panel.urls) }
                    }
                }
                Button("Paste") { shelf.paste() }.buttonStyle(.plain).font(.system(size: 11)).keyboardShortcut("v")
                if shelf.busy { ProgressView().controlSize(.mini) }
                Spacer()
                Button("Preview") { QuickLookController.shared.show(selectedURLs) }.buttonStyle(.plain).font(.system(size: 11)).disabled(selection.isEmpty).keyboardShortcut(.space, modifiers: [])
                Button { model.airDrop(selectedURLs) } label: { Label("AirDrop", systemImage: "airplay.audio").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.bordered).tint(nookAccent).disabled(selection.isEmpty)
                Menu { Button("AirDrop clipboard text / link") {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        if let url = URL(string: text), ["https", "http"].contains(url.scheme ?? "") { model.airDrop([url]) }
                        else { model.airDrop([text]) }
                    }
                } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 18)
            }
        }.onChange(of: shelf.items) { _, values in selection.formIntersection(Set(values.map(\.id))) }
    }
}

/// AppKit publishes one pasteboard item per selected file so Finder receives the whole selection.
private struct FileDragTile: NSViewRepresentable {
    var url: URL
    var name: String
    var selected: Bool
    var urls: [URL]
    var click: (NSEvent) -> Void
    var dragging: (Bool) -> Void
    func makeNSView(context: Context) -> FileDragHostingView { FileDragHostingView(rootView: AnyView(EmptyView())) }
    func updateNSView(_ view: FileDragHostingView, context: Context) {
        view.rootView = AnyView(VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().frame(width: 42, height: 42)
            Text(name).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).frame(height: 26)
        }.padding(8).frame(maxWidth: .infinity)
            .background(selected ? nookAccent.opacity(0.13) : .white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white).accessibilityLabel(name))
        view.urls = urls; view.click = click; view.dragging = dragging
    }
}

private final class FileDragHostingView: NSHostingView<AnyView> {
    var urls: [URL] = []
    var click: ((NSEvent) -> Void)?
    var dragging: ((Bool) -> Void)?
    private var down: NSPoint?
    private var started = false
    private let fileSource = FileDragSource()
    override func mouseDown(with event: NSEvent) { down = event.locationInWindow; started = false }
    override func mouseUp(with event: NSEvent) {
        if !started { click?(event) }; down = nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard !started, let down, hypot(event.locationInWindow.x - down.x, event.locationInWindow.y - down.y) > 4 else { return }
        let point = convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, 4)) * 5
            item.setDraggingFrame(NSRect(x: point.x + offset - 20, y: point.y + offset - 20, width: 40, height: 40),
                                  contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        guard !items.isEmpty else { return }
        started = true; dragging?(true)
        fileSource.ended = { [weak self] in self?.down = nil; self?.dragging?(false) }
        beginDraggingSession(with: items, event: event, source: fileSource)
    }
}

private final class FileDragSource: NSObject, NSDraggingSource {
    var ended: (() -> Void)?
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        ended?(); ended = nil
    }
}
