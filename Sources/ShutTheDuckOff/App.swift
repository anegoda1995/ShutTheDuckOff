import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = StatusController()

    func applicationDidFinishLaunching(_ notification: Notification) { controller.start() }

    func applicationWillTerminate(_ notification: Notification) { controller.shutdown() }
}

@main
enum ShutTheDuckOff {
    static let delegate = AppDelegate()   // NSApplication holds its delegate weakly
    static var terminationSource: DispatchSourceSignal?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        // launchd stops the agent with SIGTERM (logout, uninstall): stop protecting cleanly.
        signal(SIGTERM, SIG_IGN)
        terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminationSource?.setEventHandler { NSApp.terminate(nil) }
        terminationSource?.resume()
        app.run()
    }
}
