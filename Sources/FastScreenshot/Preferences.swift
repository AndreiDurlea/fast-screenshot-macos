import Combine
import Foundation

final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var trigger: Trigger? { didSet { save(trigger, for: Key.trigger) } }
    @Published var target: CaptureTarget { didSet { defaults.set(target.rawValue, forKey: Key.target) } }
    @Published var delayMs: Int { didSet { defaults.set(delayMs, forKey: Key.delay) } }
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled) } }
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: Key.onboarded) } }

    static let delayRange = 60...500

    private let defaults = UserDefaults.standard

    private enum Key {
        static let trigger = "trigger"
        static let target = "target"
        static let delay = "delayMs"
        static let enabled = "enabled"
        static let onboarded = "onboarded"
    }

    private init() {
        defaults.register(defaults: [Key.target: CaptureTarget.clipboard.rawValue, Key.delay: 120, Key.enabled: true])
        trigger = defaults.data(forKey: Key.trigger).flatMap { try? JSONDecoder().decode(Trigger.self, from: $0) }
        target = CaptureTarget(rawValue: defaults.string(forKey: Key.target) ?? "") ?? .clipboard
        delayMs = defaults.integer(forKey: Key.delay)
        enabled = defaults.bool(forKey: Key.enabled)
        onboarded = defaults.bool(forKey: Key.onboarded)
        if trigger == nil { importLegacyConfig() }
    }

    private func save<T: Encodable>(_ value: T?, for key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func importLegacyConfig() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/fast-screenshot/config.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let trigger = json["trigger"] as? [String: Any]
        else { return }

        if let button = trigger["mouseButton"] as? Int, button >= 2 {
            self.trigger = Trigger(inputs: [.mouseButton(Int64(button))])
        } else if let code = trigger["keyCode"] as? Int {
            self.trigger = Trigger(inputs: [.key(code: Int64(code), label: Input.keyLabel(code: Int64(code), characters: nil))])
        }
        if let target = (json["target"] as? String).flatMap(CaptureTarget.init(rawValue:)) { self.target = target }
        if let delay = json["delayMs"] as? Int, Self.delayRange.contains(delay) { delayMs = delay }
    }
}
