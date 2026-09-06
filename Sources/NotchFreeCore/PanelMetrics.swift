import Foundation

public struct PanelSize: Equatable, Sendable {
    public let width: Double
    public let height: Double
}

/// Shared by the SwiftUI shape and AppKit pointer/drop bounds.
public enum PanelMetrics {
    public static let expandedHeight = 212.0
    public static let widgetHeight = 132.0
    public static let spacing = 8.0
    public static let bottomPadding = 8.0
    public static let messageHeight = 34.0
    public static let trayErrorHeight = 28.0
    public static let traySpacing = 8.0
    public static let shadowGutter = 32.0

    public static func visibleSize(notchWidth: Double, notchHeight: Double,
                                   panelWidth: Double, availableWidth: Double,
                                   expanded: Bool, activity: Bool, compact: Bool,
                                   message: Bool, trayError: Bool) -> PanelSize {
        let width = expanded ? panelWidth : activity ? max(notchWidth + 130, 360) : notchWidth + (compact ? 104 : 0)
        let notices = (message ? messageHeight + spacing : 0) + (trayError ? trayErrorHeight + traySpacing : 0)
        let extraHeight = expanded ? expandedHeight + notices : activity ? 48 : 3
        return PanelSize(width: max(0, min(availableWidth, width)), height: notchHeight + extraHeight)
    }

    public static func envelopeHeight(notchHeight: Double) -> Double {
        notchHeight + expandedHeight + messageHeight + spacing + trayErrorHeight + traySpacing + shadowGutter
    }
}
