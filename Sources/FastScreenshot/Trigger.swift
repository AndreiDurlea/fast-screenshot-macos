import CoreGraphics
import Foundation

enum InputID: Hashable {
    case mouse(Int64)
    case key(Int64)
}

enum Input: Hashable, Codable {
    case mouseButton(Int64)
    case key(code: Int64, label: String)
    case modifier(code: Int64)

    var id: InputID {
        switch self {
        case .mouseButton(let button): .mouse(button)
        case .key(let code, _), .modifier(let code): .key(code)
        }
    }

    var isModifier: Bool {
        if case .modifier = self { return true }
        return false
    }

    var isMouse: Bool {
        if case .mouseButton = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .mouseButton(0): "Left"
        case .mouseButton(1): "Right"
        case .mouseButton(2): "Middle"
        case .mouseButton(let button): "\(button)"
        case .key(_, let label): label
        case .modifier(let code): Self.modifiers[code]?.label ?? "Key \(code)"
        }
    }

    var title: String {
        switch self {
        case .mouseButton(0): "Left click"
        case .mouseButton(1): "Right click"
        case .mouseButton(2): "Middle button"
        case .mouseButton(let button): "Mouse button \(button)"
        default: label
        }
    }

    static func modifierFlag(for code: Int64) -> CGEventFlags? {
        modifiers[code]?.flag
    }

    static func keyLabel(code: Int64, characters: String?) -> String {
        if let name = namedKeys[code] { return name }
        if let characters, let scalar = characters.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar), !characters.trimmingCharacters(in: .whitespaces).isEmpty {
            return characters.uppercased()
        }
        return "Key \(code)"
    }

    private static let modifiers: [Int64: (label: String, flag: CGEventFlags)] = [
        55: ("⌘", .maskCommand), 54: ("Right ⌘", .maskCommand),
        56: ("⇧", .maskShift), 60: ("Right ⇧", .maskShift),
        58: ("⌥", .maskAlternate), 61: ("Right ⌥", .maskAlternate),
        59: ("⌃", .maskControl), 62: ("Right ⌃", .maskControl),
        63: ("fn", .maskSecondaryFn),
    ]

    private static let namedKeys: [Int64: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "⌦", 53: "Esc",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑", 114: "Help",
    ]
}

struct Trigger: Equatable, Codable {
    var inputs: [Input]

    var ids: Set<InputID> { Set(inputs.map(\.id)) }
    var title: String { inputs.map(\.title).joined(separator: " + ") }
    var hasMouseButton: Bool { inputs.contains(where: \.isMouse) }

    var isValid: Bool {
        let hasModifier = inputs.contains(where: \.isModifier)
        let usesPrimaryClick = inputs.contains { if case .mouseButton(let b) = $0 { return b < 2 } else { return false } }
        return !inputs.isEmpty && !inputs.allSatisfy(\.isModifier) && (!usesPrimaryClick || hasModifier)
    }
}

enum CaptureTarget: String, Codable, CaseIterable, Identifiable {
    case clipboard
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipboard: "Clipboard"
        case .file: "File"
        }
    }
}
