import AppKit
import CoreAudio

/// The menu bar item and the decision loop: other apps' sound is protected only while some app (a call) uses a
/// microphone, plus a short grace period after it stops.
final class StatusController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var toggle = NSMenuItem(title: L("Keep other apps at full volume during calls"),
                                         action: #selector(toggleEnabled), keyEquivalent: "")
    private lazy var permissionItem = NSMenuItem(title: L("Allow System Audio Recording…"),
                                                 action: #selector(askPermission), keyEquivalent: "")

    private let watcher = ProcessWatcher()
    private var protector: Protector?
    private var lastCall: Date?
    private var lastError: String?
    private var timer: Timer?
    private let ownPID = getpid()

    /// Call apps release and reopen the mic around hang-up; keep protecting a little longer than the call.
    private let gracePeriod: TimeInterval = 4
    /// Protect this device instead of the default output (debugging and loopback tests).
    private let deviceOverride = ProcessInfo.processInfo.environment["STDO_DEVICE"].flatMap { AudioObjectID($0) }

    static let pluginDirectory = NSHomeDirectory() + "/Library/Application Support/ShutTheDuckOff/vlc-plugins"
    private var vlcPluginInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.pluginDirectory + "/libnoduck_plugin.dylib")
    }

    /// Microphone users that are not calls. More can be added with
    /// `defaults write io.github.anegoda1995.shuttheduckoff IgnoredApps -array <bundle ID prefix or process name> ...`
    private let builtInIgnored = ["com.apple.siri", "com.apple.assistant", "com.apple.corespeech", "com.apple.dictation",
                                  "com.apple.SpeechRecognitionCore", "corespeechd", "assistantd", "SiriNCService",
                                  "localspeechrecognition", "DictationIM", "speechrecognitiond"]

    private var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "Enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "Enabled") }
    }

    func start() {
        statusItem.autosaveName = "ShutTheDuckOff"
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        toggle.target = self
        permissionItem.target = self
        let quit = NSMenuItem(title: L("Quit ShutTheDuckOff"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        [statusLine, .separator(), toggle, permissionItem, .separator(), quit].forEach(menu.addItem)
        statusItem.menu = menu

        exportVLCPluginPath()
        if SystemAudioPermission.status() == .unknown {
            SystemAudioPermission.request { [weak self] _ in self?.evaluate() }
        }
        var address = CA.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(CA.system, &address, .main) { [weak self] _, _ in self?.evaluate() }
        watcher.onChange = { [weak self] in self?.evaluate() }
        watcher.start()
        // Calls are noticed through the watcher; the timer ends the grace period.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.evaluate() }
        Log.info("started, pid \(ownPID)")
        evaluate()
    }

    func shutdown() {
        protector?.stop()
        protector = nil
    }

    private func evaluate() {
        guard enabled, SystemAudioPermission.status() == .authorized else {
            stopProtecting()
            render(enabled ? L("No System Audio Recording permission") : L("Off"), look: .off)
            return
        }
        let processes = AudioProcesses.all()
        let callers = processes.filter { $0.isRunningInput && $0.pid != ownPID && !isIgnored($0) }
        if !callers.isEmpty { lastCall = Date() }
        guard let lastCall, Date().timeIntervalSince(lastCall) < gracePeriod else {
            stopProtecting()
            render(L("Waiting for a call"), look: .waiting)
            return
        }

        let device = deviceOverride ?? CA.defaultOutputDevice()
        // Never tap the call apps, this app (its replay must not loop back) or apps that are immune on their own
        // (VLC with the noduck plugin: no extra latency, no echo when sharing the whole screen).
        var exclude = Set(callers.map(\.object))
        exclude.insert(CA.processObject(for: ownPID))
        if vlcPluginInstalled {
            exclude.formUnion(processes.filter { $0.bundleID.hasPrefix("org.videolan.vlc") }.map(\.object))
        }
        exclude.remove(AudioObjectID(kAudioObjectUnknown))

        let names = Set(callers.map(AudioProcesses.displayName)).sorted().joined(separator: ", ")
        let protecting = String(format: L("Call (%@): other apps stay at full volume"), names)

        // A new output device needs a new tap. New call apps are taken out of the running one; apps that went
        // away need nothing.
        if let protector, protector.device == device, exclude.isSubset(of: protector.excluded) || protector.exclude(exclude) {
            render(protecting, look: .active)
            return
        }
        stopProtecting()
        do {
            protector = try Protector(device: device, excluding: exclude)
            lastError = nil
            render(protecting, look: .active)
        } catch {
            if lastError != "\(error)" { Log.info("cannot protect: \(error)") }
            lastError = "\(error)"
            render(String(format: L("Error: %@"), "\(error)"), look: .off)
        }
    }

    private func stopProtecting() {
        protector?.stop()
        protector = nil
    }

    private func isIgnored(_ process: AudioProcess) -> Bool {
        let ignored = builtInIgnored + (UserDefaults.standard.stringArray(forKey: "IgnoredApps") ?? [])
        return ignored.contains { entry in
            (!process.bundleID.isEmpty && process.bundleID.hasPrefix(entry))
                || entry.caseInsensitiveCompare(process.executable) == .orderedSame
        }
    }

    /// VLC started from the Dock or Finder finds the noduck plugin through this variable.
    private func exportVLCPluginPath() {
        guard vlcPluginInstalled else { return }
        let launchctl = Process()
        launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        launchctl.arguments = ["setenv", "VLC_PLUGIN_PATH", Self.pluginDirectory]
        try? launchctl.run()
    }

    /// The menu bar icon: drawings bundled as template images (MenuWaitingTemplate.png and @2x, ...), SF Symbols when
    /// the app runs outside its bundle (swift run).
    private enum Look: String {
        case waiting, active, off

        var image: NSImage? {
            if let drawn = NSImage(named: "Menu\(rawValue.capitalized)Template") { return drawn }
            let symbol = switch self {
            case .waiting: "speaker.wave.2"
            case .active: "speaker.wave.2.fill"
            case .off: "speaker.slash"
            }
            return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }

    private func render(_ text: String, look: Look) {
        if statusLine.title != text { statusLine.title = text }
        toggle.state = enabled ? .on : .off
        permissionItem.isHidden = SystemAudioPermission.status() == .authorized
        guard let button = statusItem.button, button.accessibilityIdentifier() != look.rawValue else { return }
        let image = look.image
        image?.isTemplate = true
        image?.accessibilityDescription = text
        button.image = image
        button.setAccessibilityIdentifier(look.rawValue)
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        evaluate()
    }

    @objc private func askPermission() {
        if SystemAudioPermission.status() == .unknown {
            SystemAudioPermission.request { [weak self] _ in self?.evaluate() }
        } else {
            SystemAudioPermission.openSettings()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
