import SwiftUI

struct SettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var status = SystemStatus.shared

    var body: some View {
        Form {
            if status.loginBlocked || !status.accessibilityTrusted {
                Section {
                    if !status.accessibilityTrusted {
                        WarningRow(text: "Accessibility is off, so the trigger does nothing.",
                                   button: "Open Settings", action: status.requestAccessibility)
                    }
                    if status.loginBlocked {
                        WarningRow(text: "macOS blocked Fast Screenshot from opening at login and staying on.",
                                   button: "Open Settings", action: status.openLoginItemsSettings)
                    }
                }
            }

            Section {
                TriggerDemo()
            } footer: {
                Text("Hold the trigger, move the pointer to draw the area, release to capture.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            Section {
                Toggle("Enabled", isOn: $preferences.enabled)
                LabeledContent("Trigger") { TriggerRecorder() }
                Picker("Save to", selection: $preferences.target) {
                    ForEach(CaptureTarget.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent("Start delay") {
                    Stepper("\(preferences.delayMs) ms", value: $preferences.delayMs, in: Preferences.delayRange, step: 10)
                }
            } footer: {
                Text("Time between opening the crosshair and starting the selection. Raise it if the crosshair opens but nothing gets selected.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct WarningRow: View {
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(button, action: action)
        }
    }
}
