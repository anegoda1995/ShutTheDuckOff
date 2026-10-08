import AppKit

/// The "System Audio Recording Only" permission. There is no public API to ask for it, and creating a tap does
/// not show the prompt, so this talks to TCC directly. Without the permission a tap delivers silence, so the app
/// never mutes anything until this reports `.authorized`.
enum SystemAudioPermission {
    enum Status { case authorized, denied, unknown }

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static var cached: (date: Date, status: Status)?

    /// Cached for a few seconds: the controller asks every second.
    static func status() -> Status {
        if let cached, Date().timeIntervalSince(cached.date) < 5 { return cached.status }
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessPreflight") else { return .unknown }
        let status: Status
        switch unsafeBitCast(symbol, to: PreflightFunction.self)(service, nil) {
        case 0: status = .authorized
        case 1: status = .denied
        default: status = .unknown
        }
        cached = (Date(), status)
        return status
    }

    /// Shows the system prompt if the user has not decided yet.
    static func request(_ completion: @escaping (Bool) -> Void) {
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessRequest") else { completion(false); return }
        unsafeBitCast(symbol, to: RequestFunction.self)(service, nil) { granted in
            DispatchQueue.main.async {
                cached = nil
                completion(granted)
            }
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
