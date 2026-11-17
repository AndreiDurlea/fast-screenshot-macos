import SwiftUI

struct TriggerRecorder: View {
    @ObservedObject private var preferences = Preferences.shared
    @ObservedObject private var status = SystemStatus.shared
    @State private var recording = false
    @State private var silent = false
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(recording ? "Hold the keys or buttons, then release…" : preferences.trigger?.title ?? "Not set")
                    .foregroundStyle(recording || preferences.trigger == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(minWidth: 190, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(recording ? Color.accentColor : .clear))
                Button(recording ? "Cancel" : "Record", action: toggle)
                    .disabled(!status.accessibilityTrusted)
            }
            if recording {
                Text(silent
                     ? "Nothing received. Some mouse buttons switch modes inside the mouse and never reach macOS; remap them in the mouse's software or pick another one."
                     : "Press one key or button, or several together, with or without ⌘ ⌃ ⌥ ⇧. Left and right click count only together with a modifier. Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        if recording {
            stop()
            return
        }
        recording = true
        silent = false
        attempt += 1
        let current = attempt
        Snapper.shared.record { trigger in
            guard current == attempt else { return }
            if let trigger { preferences.trigger = trigger }
            recording = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if recording, current == attempt, LiveInput.shared.pressed.isEmpty { silent = true }
        }
    }

    private func stop() {
        guard recording else { return }
        attempt += 1
        Snapper.shared.cancelRecording()
        recording = false
    }
}
