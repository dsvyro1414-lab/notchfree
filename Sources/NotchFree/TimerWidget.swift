import SwiftUI
import AppKit
import NotchFreeCore

struct TimerWidget: View {
    @Environment(\.nookAccent) private var accent
    @ObservedObject var model: AppModel
    @State private var draft: TimerDurationInput?
    @State private var original: TimerDurationInput?
    private var timer: Countdown { model.library.timer }
    private var displayed: TimerDurationInput { draft ?? TimerDurationInput(duration: timer.remaining(at: model.now)) }
    private var canEdit: Bool { !timer.isRunning && !timer.completed }
    private var valid: Bool { draft == nil || draft?.duration != nil }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Label("Focus timer", systemImage: "timer").foregroundStyle(accent)
                Spacer()
                Text(valid ? timer.motivation : "Enter 00:00:01–23:59:59.")
                    .foregroundStyle(valid ? Color.secondary : .orange)
            }.font(.system(size: 11)).frame(height: 16)
            HStack(spacing: 0) {
                digit("Hours", keyPath: \.hours)
                Text(":").frame(width: 17)
                digit("Minutes", keyPath: \.minutes)
                Text(":").frame(width: 17)
                digit("Seconds", keyPath: \.seconds)
            }.font(.system(size: 52, weight: .light, design: .rounded)).monospacedDigit()
                .frame(maxWidth: .infinity).frame(height: 62)
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent).frame(width: geometry.size.width * timer.progress(at: model.now))
                    }
            }.frame(height: 3).padding(.vertical, 3)
                .accessibilityLabel("Timer progress")
                .accessibilityValue("\(Int(timer.progress(at: model.now) * 100)) percent")
            HStack(spacing: 6) {
                ForEach([5, 15, 25, 50], id: \.self) { minutes in
                    Button {
                        discardDraft()
                        model.library.timer.configure(seconds: Double(minutes * 60))
                        model.saveNow(); model.feedback()
                    } label: {
                        Text("\(minutes) min").font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9).frame(height: 28)
                            .background(.white.opacity(timer.duration == Double(minutes * 60) ? 0.13 : 0.055), in: Capsule())
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .disabled(!canEdit).accessibilityLabel("Set timer to \(minutes) minutes")
                }
                Spacer(minLength: 8)
                Button { discardDraft(); model.library.timer.reset(); model.saveNow(); model.feedback() } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium)).frame(width: 72, height: 28)
                        .background(.white.opacity(0.08), in: Capsule()).contentShape(Capsule())
                }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                    .disabled(timer.phase == .ready && draft == nil)
                    .help("Stop and return to \(TimerDurationInput(duration: timer.duration).formatted).")
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold)).frame(width: 96, height: 28)
                        .foregroundStyle(.black).background(accent, in: Capsule())
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!valid).opacity(valid ? 1 : 0.4)
            }.frame(height: 28)
        }.padding(.horizontal, 14).frame(height: PanelMetrics.widgetHeight)
            .onDisappear { _ = commitDraft(); discardDraft() }
    }

    private var primaryTitle: String {
        switch timer.phase {
        case .ready: return "Start"
        case .running: return "Pause"
        case .paused: return "Resume"
        case .completed: return "Start again"
        }
    }
    private func digit(_ label: String, keyPath: WritableKeyPath<TimerDurationInput, String>) -> some View {
        Group {
            if canEdit {
                TimerDigitsField(text: Binding(get: { displayed[keyPath: keyPath] }, set: { text in
                    beginEditing(); draft?[keyPath: keyPath] = text
                }), label: label, begin: beginEditing, commit: commitDraft, cancel: discardDraft)
            } else {
                Text(displayed[keyPath: keyPath]).accessibilityLabel("\(label): \(displayed[keyPath: keyPath])")
            }
        }.frame(width: 74, height: 62)
    }
    private func beginEditing() {
        if draft == nil {
            let input = TimerDurationInput(duration: timer.remaining(at: model.now))
            original = input; draft = input
        }
        if !model.presentation.editing { model.presentation.editing = true }
    }
    @discardableResult private func commitDraft() -> Bool {
        guard let draft else { return true }
        guard let duration = draft.duration else { return false }
        if draft != original { model.library.timer.configure(seconds: duration); model.saveNow() }
        discardDraft(); return true
    }
    private func discardDraft() {
        draft = nil; original = nil; model.presentation.editing = false
        // End the field editor before a preset, Reset or Start can change the model.
        if TimerTextField.isEditing(in: NSApp.keyWindow) { NSApp.keyWindow?.makeFirstResponder(nil) }
    }
    private func primaryAction() {
        guard commitDraft() else { return }
        let now = Date()
        model.now = now
        switch timer.phase {
        case .running: model.library.timer.pause(now: now)
        case .paused: model.library.timer.resume(now: now)
        case .ready, .completed: model.library.timer.start(seconds: timer.duration, now: now)
        }
        model.saveNow(); model.feedback()
    }
}

/// A small native text bridge provides select-all on click and standard Tab navigation.
private struct TimerDigitsField: NSViewRepresentable {
    @Binding var text: String
    var label: String
    var begin: () -> Void
    var commit: () -> Bool
    var cancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> TimerTextField {
        let field = TimerTextField()
        field.delegate = context.coordinator
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.alignment = .center; field.textColor = .white
        let font = NSFont.monospacedDigitSystemFont(ofSize: 52, weight: .light)
        field.font = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 52) } ?? font
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel(label)
        field.setAccessibilityHelp("Click to edit. Tab changes the field. Return confirms. Escape cancels.")
        return field
    }
    func updateNSView(_ field: TimerTextField, context: Context) {
        context.coordinator.parent = self
        // AppKit owns the live selection; writing during editing would replace it on every tick.
        if field.currentEditor() == nil, field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TimerDigitsField
        init(_ parent: TimerDigitsField) { self.parent = parent }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.begin() }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            // Tab moves to another timer field; keep the same draft and hover lock.
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self else { return }
                if TimerTextField.isEditing(in: field?.window) { return }
                if !self.parent.commit() { self.parent.cancel() }
            }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if parent.commit() { control.window?.makeFirstResponder(nil) }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.cancel(); control.window?.makeFirstResponder(nil); return true
            default: return false
            }
        }
    }
}

private final class TimerTextField: NSTextField {
    static func isEditing(in window: NSWindow?) -> Bool {
        guard let window, let root = window.contentView else { return false }
        func containsEditor(_ view: NSView) -> Bool {
            if let field = view as? TimerTextField, let editor = field.currentEditor(), editor === window.firstResponder { return true }
            return view.subviews.contains(where: containsEditor)
        }
        return containsEditor(root)
    }
    override func mouseDown(with event: NSEvent) {
        guard isEditable else { return }
        super.mouseDown(with: event)
        currentEditor()?.selectAll(nil)
    }
}
