import SwiftUI

@main
struct FastScreenshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var status = SystemStatus.shared

    var body: some Scene {
        MenuBarExtra("Fast Screenshot", systemImage: "camera.viewfinder") {
            if !status.accessibilityTrusted {
                Button("Allow Accessibility…") { Windows.shared.showOnboarding() }
            }
            if status.loginBlocked {
                Button("Allow Fast Screenshot in Login Items…", action: status.openLoginItemsSettings)
            }
            if !status.accessibilityTrusted || status.loginBlocked {
                Divider()
            }
            Toggle("Enabled", isOn: $preferences.enabled)
            Text("Trigger: \(preferences.trigger?.title ?? "not set")")
            Text("Saves to: \(preferences.target.title)")
            Divider()
            Button("Settings…") { Windows.shared.showSettings() }
                .keyboardShortcut(",")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Windows.shared.showSettings()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = SystemStatus.shared
        let center = DistributedNotificationCenter.default()
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current }

        if SystemStatus.runsAsAgent {
            // launchd keeps this copy alive, so a copy opened from Finder makes way for it.
            if !others.isEmpty { center.postNotificationName(SystemStatus.quitNotification, object: nil, deliverImmediately: true) }
        } else {
            let agentWasRunning = status.agentRunning()
            if status.startAgent() {
                if agentWasRunning {
                    center.postNotificationName(SystemStatus.showNotification, object: nil, deliverImmediately: true)
                    // distnoted drops a notification whose sender exits before it is delivered.
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                }
                exit(0)
            }
        }

        observers.append(center.addObserver(forName: SystemStatus.showNotification, object: nil, queue: .main) { _ in
            Windows.shared.showSettings()
        })
        if !SystemStatus.runsAsAgent {
            observers.append(center.addObserver(forName: SystemStatus.quitNotification, object: nil, queue: .main) { _ in
                exit(0)
            })
        }

        if status.accessibilityTrusted { Snapper.shared.start() }

        let preferences = Preferences.shared
        if !preferences.onboarded || !status.accessibilityTrusted || preferences.trigger == nil
            || CommandLine.arguments.contains("--onboarding") {
            Windows.shared.showOnboarding()
        } else if CommandLine.arguments.contains("--settings") || status.loginBlocked {
            Windows.shared.showSettings()
        }
    }
}

final class Windows {
    static let shared = Windows()

    private var settings: NSWindow?
    private var onboarding: NSWindow?

    func showSettings() {
        settings = settings ?? makeWindow(title: "Fast Screenshot Settings", content: SettingsView())
        present(settings)
    }

    func showOnboarding() {
        onboarding = onboarding ?? makeWindow(title: "Welcome to Fast Screenshot", content: OnboardingView { [weak self] in
            Preferences.shared.onboarded = true
            self?.onboarding?.close()
        })
        present(onboarding)
    }

    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
