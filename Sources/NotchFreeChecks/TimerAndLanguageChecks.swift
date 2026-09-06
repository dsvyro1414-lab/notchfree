import Foundation
import NotchFreeCore

extension Checks {
    static func timerInputChecks() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        try expect(TimerDurationInput(duration: 3_661).formatted == "01:01:01", "Hours, minutes and seconds format independently")
        try expect(TimerDurationInput(duration: 59.1).formatted == "00:01:00", "The countdown rounds remaining fractions upward")
        try expect(TimerDurationInput(hours: "0", minutes: "5", seconds: "0").duration == 300, "Single digit input is accepted before normalization")
        try expect(TimerDurationInput(hours: "23", minutes: "59", seconds: "59").duration == 86_399, "Maximum supported duration is accepted")
        for input in [
            TimerDurationInput(hours: "00", minutes: "00", seconds: "00"),
            TimerDurationInput(hours: "24", minutes: "00", seconds: "00"),
            TimerDurationInput(hours: "00", minutes: "60", seconds: "00"),
            TimerDurationInput(hours: "00", minutes: "00", seconds: "60"),
            TimerDurationInput(hours: "", minutes: "05", seconds: "00"),
            TimerDurationInput(hours: "-1", minutes: "05", seconds: "00"),
            TimerDurationInput(hours: "00", minutes: "1.5", seconds: "00"),
            TimerDurationInput(hours: "00", minutes: "abc", seconds: "00"),
            TimerDurationInput(hours: "00", minutes: "500", seconds: "00")
        ] { try expect(input.duration == nil, "Invalid keyboard draft is rejected: \(input.formatted)") }
        try expect(TimerDurationInput(duration: .infinity).formatted == "00:00:00", "Non-finite display values cannot trap")

        var timer = Countdown()
        try expect(timer.motivation == "Lock in now.", "Ready timer has its motivational caption")
        for minutes in [5, 15, 25, 50] {
            try expect(timer.configure(seconds: Double(minutes * 60)), "Focus preset \(minutes) minutes is accepted")
            try expect(!timer.isRunning && timer.remaining(at: now) == Double(minutes * 60), "A preset configures without starting")
        }
        let selected = timer
        try expect(!timer.configure(seconds: 0) && timer == selected, "Invalid configuration preserves the selected timer")
        timer.start(seconds: .nan, now: now)
        try expect(timer == selected, "Invalid start cannot create an unusable deadline")
        timer.configure(seconds: 300); timer.start(seconds: timer.duration, now: now)
        try expect(timer.motivation == "Focus now." && timer.progress(at: now.addingTimeInterval(150)) == 0.5, "Running timer shows progress and focus caption")
        let running = timer
        try expect(!timer.configure(seconds: 900) && timer == running, "Running duration requires Pause before editing")
        timer.pause(now: now.addingTimeInterval(150))
        try expect(timer.motivation == "Take a breath." && timer.remaining(at: now.addingTimeInterval(900)) == 150, "Pause freezes the remaining time and changes its caption")
        timer.configure(seconds: 90)
        try expect(timer.phase == .paused && timer.duration == 90 && timer.pausedRemaining == 90, "Editing a paused timer rebases duration without resuming")
        try expect(timer.progress(at: now) == 0, "Edited paused duration resets the progress baseline")
        timer = try JSONDecoder().decode(Countdown.self, from: JSONEncoder().encode(timer))
        try expect(timer.pausedRemaining == 90 && timer.duration == 90, "Edited paused duration survives relaunch")
        timer.resume(now: now)
        try expect(timer.remaining(at: now.addingTimeInterval(30)) == 60, "Resume uses the edited remaining duration")
        timer.reset()
        try expect(timer.phase == .ready && timer.remaining(at: now) == 90, "Reset restores the newly selected duration")
        try expect(timer.deadline == nil && timer.pausedRemaining == nil && timer.progress(at: now) == 0, "Reset cancels the running deadline and clears progress")
        timer.start(seconds: 90, now: now); timer.pause(now: now.addingTimeInterval(40)); timer.reset()
        try expect(timer.phase == .ready && timer.remaining(at: now) == 90, "Reset from Pause restores the full selected duration")
        timer.start(seconds: 1, now: now); timer.pause(now: now.addingTimeInterval(2))
        try expect(timer.completed && timer.motivation == "You did it. Take a break.", "Pause at expiry completes instead of creating a zero paused timer")
        timer.resume(now: now)
        try expect(!timer.isRunning && timer.progress(at: now) == 1, "Completed timer cannot resume a zero duration")
        timer.start(seconds: timer.duration, now: now)
        try expect(timer.isRunning && !timer.completed, "Start again repeats the completed duration")
        timer.expire(now: now.addingTimeInterval(2)); timer.reset()
        try expect(timer.phase == .ready && !timer.completed && timer.remaining(at: now) == 1, "Reset after completion clears the completed flag")

        let legacy = Data("{\"duration\":1500,\"completed\":false,\"pausedRemaining\":87}".utf8)
        let restored = try JSONDecoder().decode(Countdown.self, from: legacy)
        try expect(restored.duration == 1500 && restored.remaining(at: now) == 87, "Existing persisted countdown format remains compatible")
    }

    static func englishChecks() throws {
        print("System locale under test: \(Locale.current.identifier)")
        let date = Date(timeIntervalSince1970: 1_789_272_000)
        try expect(AppEnglish.month(date) == "Sep", "Month names use English regardless of system locale")
        let dateLabels = [AppEnglish.month(date), AppEnglish.weekday(date), AppEnglish.day(date), AppEnglish.time(date)]
        try expect(dateLabels.allSatisfy { $0.range(of: "[\\p{Cyrillic}]", options: .regularExpression) == nil }, "All calendar date labels use English formatting")
        let external = "\u{041E}\u{0448}\u{0438}\u{0431}\u{043A}\u{0430}"
        for operation: AppFailure.Operation in [.loadLibrary, .saveLibrary, .loadTray, .importFile, .removeFile, .share, .startup, .media, .calendar, .camera] {
            let error = NSError(domain: "External", code: 1, userInfo: [NSLocalizedDescriptionKey: external])
            let message = AppFailure.message(error, operation: operation)
            try expect(!message.contains(external) && !message.isEmpty, "External localized error is replaced for \(operation)")
        }
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError, userInfo: [NSLocalizedDescriptionKey: external])
        try expect(AppFailure.message(denied, operation: .importFile).contains("denied"), "File permission denial retains an actionable English reason")
        let missing = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        try expect(AppFailure.message(missing, operation: .importFile).contains("no longer available"), "Missing file error retains its cause")
        let full = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        try expect(AppFailure.message(full, operation: .saveLibrary).contains("free disk space"), "Full disk error explains how to recover")
        try expect(AppFailure.message(StoreError.corrupted("library.json"), operation: .loadLibrary).contains("preserved"), "Storage recovery guidance survives English error mapping")
    }
}
