import Foundation
import os

enum Log {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "shuttheduckoff", category: "app")

    static func info(_ message: String) { logger.log("\(message, privacy: .public)") }
}

/// Localized string from the app bundle; the English text is the key.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
