import SwiftUI

struct OnboardingView: View {
    let finish: () -> Void

    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var status = SystemStatus.shared
    @State private var waitedForGrant = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fast Screenshot").font(.title2.weight(.semibold))
                    Text("Hold the trigger, drag over an area, release to capture it.")
                        .foregroundStyle(.secondary)
                }
            }

            step(1, "Allow Accessibility", done: status.accessibilityTrusted) {
                Text("Fast Screenshot turns the trigger into a mouse drag inside the macOS screenshot crosshair, which needs Accessibility.")
                    .stepDetail()
                if !status.accessibilityTrusted {
                    HStack {
                        Button("Open System Settings") {
                            status.requestAccessibility()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { waitedForGrant = true }
                        }
                        if waitedForGrant {
                            Button("Restart Fast Screenshot", action: status.relaunch)
                        }
                    }
                }
            }

            step(2, "Choose the trigger", done: preferences.trigger != nil) {
                Text("Press Record, then a key, a mouse button, or several together. They stop doing anything else while Fast Screenshot runs.")
                    .stepDetail()
                TriggerRecorder()
                TriggerDemo()
                Picker("Save to", selection: $preferences.target) {
                    ForEach(CaptureTarget.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            .opacity(status.accessibilityTrusted ? 1 : 0.4)
            .disabled(!status.accessibilityTrusted)

            if status.loginBlocked {
                WarningRow(text: "macOS blocked Fast Screenshot from opening at login and staying on.",
                           button: "Open Settings", action: status.openLoginItemsSettings)
            }

            HStack {
                Text("Fast Screenshot opens at login. Settings are in the menu bar icon.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: finish)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!status.accessibilityTrusted || preferences.trigger == nil)
            }
        }
        .padding(24)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func step<Content: View>(_ number: Int, _ title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.primary.opacity(0.1)).frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.weight(.semibold))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                content()
            }
        }
    }
}

private extension Text {
    func stepDetail() -> some View {
        foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
