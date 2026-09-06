import Foundation

/// An uncommitted keyboard draft never changes the persisted countdown.
public struct TimerDurationInput: Equatable, Sendable {
    public var hours: String
    public var minutes: String
    public var seconds: String
    public static let maximumDuration: TimeInterval = 86_399

    public init(hours: String, minutes: String, seconds: String) {
        self.hours = hours; self.minutes = minutes; self.seconds = seconds
    }
    public init(duration: TimeInterval) {
        let value = duration.isFinite ? Int(min(Self.maximumDuration, max(0, duration.rounded(.up)))) : 0
        hours = String(format: "%02d", value / 3600)
        minutes = String(format: "%02d", value / 60 % 60)
        seconds = String(format: "%02d", value % 60)
    }
    public var duration: TimeInterval? {
        func number(_ text: String, maximum: Int) -> Int? {
            guard (1...2).contains(text.count), text.utf8.allSatisfy({ (48...57).contains($0) }),
                  let value = Int(text), value <= maximum else { return nil }
            return value
        }
        guard let h = number(hours, maximum: 23), let m = number(minutes, maximum: 59),
              let s = number(seconds, maximum: 59) else { return nil }
        let total = h * 3600 + m * 60 + s
        return total > 0 ? TimeInterval(total) : nil
    }
    public var formatted: String { "\(hours):\(minutes):\(seconds)" }
}

extension Countdown {
    public enum Phase: Sendable { case ready, running, paused, completed }
    public var phase: Phase {
        completed ? .completed : isRunning ? .running : pausedRemaining != nil ? .paused : .ready
    }
    public var motivation: String {
        switch phase {
        case .ready: return "Lock in now."
        case .running: return "Focus now."
        case .paused: return "Take a breath."
        case .completed: return "You did it. Take a break."
        }
    }
    public func progress(at now: Date) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }
    /// Editing a paused timer selects a new duration while keeping it paused.
    @discardableResult public mutating func configure(seconds: TimeInterval) -> Bool {
        guard !isRunning, seconds.isFinite, (1...TimerDurationInput.maximumDuration).contains(seconds) else { return false }
        let wasPaused = phase == .paused
        duration = seconds; pausedRemaining = wasPaused ? seconds : nil; completed = false
        return true
    }
}
