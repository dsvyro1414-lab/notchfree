import Foundation

public enum AppEnglish {
    public static let locale = Locale(identifier: "en_US")
    public static func month(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).locale(locale)) }
    public static func weekday(_ date: Date) -> String { date.formatted(.dateTime.weekday(.narrow).locale(locale)) }
    public static func day(_ date: Date) -> String { date.formatted(.dateTime.day().locale(locale)) }
    public static func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().locale(locale)) }
}

/// Only app-owned copy crosses into the UI; OS and subprocess error text can be localized.
public enum AppFailure {
    public enum Operation: Sendable {
        case loadLibrary, saveLibrary, loadTray, importFile, removeFile, share, startup, media, calendar, camera
        var guidance: String {
            switch self {
            case .loadLibrary: return "Could not load your notes and tasks. Your existing data has been preserved."
            case .saveLibrary: return "Could not save your changes. Check available disk space and folder access, then retry."
            case .loadTray: return "Could not load the tray. Your existing files have been preserved."
            case .importFile: return "Could not add this file. Check that it is available and readable, then retry."
            case .removeFile: return "Could not move the tray copy to Trash. Check folder access, then retry."
            case .share: return "AirDrop could not finish. Check that the receiving device is available, then retry."
            case .startup: return "Could not update launch at login. Check NotchFree in System Settings > General > Login Items."
            case .media: return "Could not connect to the player. Open it, check Automation access in System Settings, then reconnect."
            case .calendar: return "Could not access your calendar. Check Calendars access in System Settings, then retry."
            case .camera: return "Could not start the camera. Check Camera access in System Settings and close other apps using the camera."
            }
        }
    }
    public static func message(_ error: Error, operation: Operation) -> String {
        if let error = error as? StoreError { return error.errorDescription ?? operation.guidance }
        let error = error as NSError
        let reason: String
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: reason = "Access to the file or folder was denied."
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: reason = "The file is no longer available."
            case NSFileWriteOutOfSpaceError: reason = "There is not enough free disk space."
            default: reason = ""
            }
        } else { reason = "" }
        return reason.isEmpty ? operation.guidance : "\(reason) \(operation.guidance)"
    }
}
