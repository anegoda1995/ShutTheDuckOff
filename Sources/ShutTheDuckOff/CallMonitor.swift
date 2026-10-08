import AppKit
import CoreAudio

struct AudioProcess {
    let object: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let executable: String
    let isRunningInput: Bool
}

enum AudioProcesses {
    /// Every process the audio server knows about (macOS 14+ process objects).
    static func all() -> [AudioProcess] {
        CA.objects(CA.system, kAudioHardwarePropertyProcessObjectList).map { object in
            let pid: pid_t = CA.value(object, kAudioProcessPropertyPID, -1)
            return AudioProcess(
                object: object,
                pid: pid,
                bundleID: CA.string(object, kAudioProcessPropertyBundleID) ?? "",
                executable: executableName(pid),
                isRunningInput: CA.value(object, kAudioProcessPropertyIsRunningInput, UInt32(0)) != 0)
        }
    }

    static func executableName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        return proc_name(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
    }

    private static let daemons = ["avconferenced": "FaceTime", "callservicesd": "FaceTime"]

    /// FaceTime for its daemons, otherwise the outermost .app the process belongs to (browser helpers included).
    static func displayName(_ process: AudioProcess) -> String {
        if let name = daemons[process.executable] { return name }
        var buffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(process.pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = String(cString: buffer)
            if let range = path.range(of: ".app/") {
                let app = String(path[..<range.lowerBound]) + ".app"
                return FileManager.default.displayName(atPath: app).replacingOccurrences(of: ".app", with: "")
            }
        }
        return process.executable.isEmpty ? "?" : process.executable
    }
}

/// Wakes the controller the moment an app starts using a microphone. A call app ducks other audio at that very
/// moment, so waiting for the next poll would leave the sound ducked for up to a second.
///
/// The audio server does not send notifications for kAudioProcessPropertyIsRunningInput. What does arrive in
/// time is kAudioProcessPropertyIsRunning (a process starts any I/O) and, for an app that already plays sound
/// when it opens the mic, kAudioDevicePropertyDeviceIsRunningSomewhere on the input device.
final class ProcessWatcher {
    var onChange: (() -> Void)?
    private var watched = Set<AudioObjectID>()

    func start() {
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDevices] {
            var address = CA.address(selector)
            AudioObjectAddPropertyListenerBlock(CA.system, &address, .main) { [weak self] _, _ in
                self?.refresh()
                self?.onChange?()
            }
        }
        refresh()
    }

    /// Listeners go away together with their objects, so only new objects need attention.
    private func refresh() {
        let processes = CA.objects(CA.system, kAudioHardwarePropertyProcessObjectList)
        let inputs = CA.objects(CA.system, kAudioHardwarePropertyDevices).filter { CA.inputStreamCount($0) > 0 }
        let targets = processes.map { ($0, kAudioProcessPropertyIsRunning) }
            + inputs.map { ($0, kAudioDevicePropertyDeviceIsRunningSomewhere) }
        for (object, selector) in targets where !watched.contains(object) {
            var address = CA.address(selector)
            AudioObjectAddPropertyListenerBlock(object, &address, .main) { [weak self] _, _ in self?.onChange?() }
        }
        watched = Set(processes + inputs)
    }
}
