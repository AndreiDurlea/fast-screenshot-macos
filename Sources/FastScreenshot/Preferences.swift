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
    static let defaultTrigger = Trigger(inputs: [.mouseButton(4)])

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
        if trigger == nil { trigger = Self.defaultTrigger }
    }

    private func save<T: Encodable>(_ value: T?, for key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

}
