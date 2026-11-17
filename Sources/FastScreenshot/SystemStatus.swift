import AppKit
import Combine
import ServiceManagement

final class SystemStatus: ObservableObject {
    static let shared = SystemStatus()

    static let agentLabel = "com.durlea.fastscreenshot"
    static let showNotification = Notification.Name("com.durlea.fastscreenshot.show")
    static let quitNotification = Notification.Name("com.durlea.fastscreenshot.quit")

    static var runsAsAgent: Bool {
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == agentLabel
    }

    private static var agentPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    private static var domain: String { "gui/\(getuid())" }

    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var loginBlocked = false

    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var ticks = 0

    private init() {
        // The new grant reaches AXIsProcessTrusted about a second after this notification.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        loginBlocked = Self.agentDisabled()
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        if trusted, !Snapper.shared.isRunning { Snapper.shared.start() }
        ticks += 1
        if ticks % 5 == 0 {
            let blocked = Self.agentDisabled()
            if blocked != loginBlocked { loginBlocked = blocked }
        }
    }

    // A LaunchAgent written by the app, rather than SMAppService: SMAppService ties an ad hoc signed agent
    // to the code it had at registration, and after a rebuild its spawn intermittently fails with a launch
    // constraint violation. Returns whether the agent copy is running.
    func startAgent() -> Bool {
        let lock = open(NSTemporaryDirectory() + "com.durlea.fastscreenshot.register.lock", O_CREAT | O_RDWR, 0o600)
        if lock >= 0 { flock(lock, LOCK_EX) }
        defer { if lock >= 0 { flock(lock, LOCK_UN); close(lock) } }

        try? SMAppService.agent(plistName: "com.durlea.fastscreenshot.agent.plist").unregister()

        let plist = Self.agentPlistContents()
        if (try? Data(contentsOf: Self.agentPlist)) != plist {
            launchctl("bootout", "\(Self.domain)/\(Self.agentLabel)")
            try? FileManager.default.createDirectory(at: Self.agentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plist.write(to: Self.agentPlist)
        }
        if !launchctl("print", "\(Self.domain)/\(Self.agentLabel)").ok {
            launchctl("bootstrap", Self.domain, Self.agentPlist.path)
        }
        loginBlocked = Self.agentDisabled()
        if loginBlocked { return false }
        launchctl("kickstart", "\(Self.domain)/\(Self.agentLabel)")

        for _ in 0..<20 {
            if agentRunning() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    func agentRunning() -> Bool {
        launchctl("print", "\(Self.domain)/\(Self.agentLabel)").output.contains("state = running")
    }

    private static func agentPlistContents() -> Data {
        let plist: [String: Any] = [
            "Label": agentLabel,
            "Program": Bundle.main.executablePath ?? "",
            "AssociatedBundleIdentifiers": [Bundle.main.bundleIdentifier ?? agentLabel],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 5,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
    }

    private static func agentDisabled() -> Bool {
        launchctl("print-disabled", domain).output.contains("\"\(agentLabel)\" => disabled")
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func requestAccessibility() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func relaunch() {
        if Self.runsAsAgent {
            exit(0)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        exit(0)
    }
}

@discardableResult
private func launchctl(_ arguments: String...) -> (ok: Bool, output: String) {
    let task = Process()
    let pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = arguments
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    guard (try? task.run()) != nil else { return (false, "") }
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    task.waitUntilExit()
    return (task.terminationStatus == 0, output)
}
