import Cocoa
import Combine

private let syntheticMarker: Int64 = 0x4653_5348

enum CapturePhase {
    case idle
    case arming
    case dragging
}

final class LiveInput: ObservableObject {
    static let shared = LiveInput()

    @Published fileprivate(set) var pressed: Set<InputID> = []
    @Published fileprivate(set) var phase = CapturePhase.idle
    @Published fileprivate(set) var lastCapture: Date?
    @Published fileprivate(set) var recording: [Input]?
}

final class Snapper {
    static let shared = Snapper()

    private let preferences = Preferences.shared
    private let live = LiveInput.shared
    private let source = CGEventSource(stateID: .hidSystemState)
    private var tap: CFMachPort?
    private var held: Set<InputID> = []
    private var phase = CapturePhase.idle { didSet { live.phase = phase } }
    private var releasedWhileArming = false

    private var recorder: ((Trigger?) -> Void)?
    private var recorded: [Input] = []
    private var recordHeld: Set<InputID> = []
    private var swallowUntilReleased: Set<InputID> = []
    private var lastTriggerEvent = Date.distantPast
    private var watchdog: Timer?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged, .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, pointer in
                Unmanaged<Snapper>.fromOpaque(pointer!).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func record(_ completion: @escaping (Trigger?) -> Void) {
        recorder?(nil)
        recorder = completion
        recorded = []
        recordHeld = []
        held = []
        live.recording = []
    }

    func cancelRecording() {
        recorder = nil
        recorded = []
        recordHeld = []
        live.recording = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Events missed while the tap was off may include releases, so nothing remembered is trusted.
            resetState()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker { return pass }

        if phase == .dragging, [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type) {
            postMouse(.leftMouseDragged, at: event.location)
            return nil
        }

        guard let (input, down) = parse(type, event) else { return pass }
        let isRepeat = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let swallow: Unmanaged<CGEvent>? = input.isModifier ? pass : nil

        if recorder != nil { return recordEvent(input, down: down, isRepeat: isRepeat) ? swallow : pass }

        if swallowUntilReleased.contains(input.id) {
            if !down { swallowUntilReleased.remove(input.id) }
            return swallow
        }

        if type != .flagsChanged, let trigger = preferences.trigger { syncModifiers(of: trigger, with: event) }
        if phase != .idle, let trigger = preferences.trigger, trigger.ids.contains(input.id) { lastTriggerEvent = Date() }

        guard preferences.enabled, let trigger = preferences.trigger, trigger.ids.contains(input.id) else {
            if isDrag(type) || isRepeat { return pass }
            if !down { updatePressed(removing: input.id) }
            return pass
        }
        // Left and right click count only while the rest of the trigger is held, so plain clicks pass through.
        let primaryClick = input.id == .mouse(0) || input.id == .mouse(1)
        if primaryClick, !held.contains(input.id),
           !(down && !isDrag(type) && held.union([input.id]).isSuperset(of: trigger.ids)) {
            return pass
        }
        if isDrag(type) || isRepeat { return swallow }

        if down {
            held.insert(input.id)
            if held.isSuperset(of: trigger.ids) { begin() }
        } else {
            held.remove(input.id)
            if phase != .idle { end() }
        }
        live.pressed = held
        return swallow
    }

    private func updatePressed(removing id: InputID) {
        if held.remove(id) != nil { live.pressed = held }
    }

    private func isDrag(_ type: CGEventType) -> Bool {
        type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged
    }

    private func parse(_ type: CGEventType, _ event: CGEvent) -> (Input, Bool)? {
        switch type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            let up = type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp
            return (.mouseButton(event.getIntegerValueField(.mouseEventButtonNumber)), !up)
        case .keyDown, .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let characters = type == .keyDown ? NSEvent(cgEvent: event)?.charactersIgnoringModifiers : nil
            return (.key(code: code, label: Input.keyLabel(code: code, characters: characters)), type == .keyDown)
        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard let flag = Input.modifierFlag(for: code) else { return nil }
            return (.modifier(code: code), event.flags.contains(flag))
        default:
            return nil
        }
    }

    private func recordEvent(_ input: Input, down: Bool, isRepeat: Bool) -> Bool {
        if isRepeat { return true }
        if case .mouseButton(let button) = input, button < 2,
           !recorded.contains(where: { $0.id == input.id }),
           !recorded.contains(where: { $0.isModifier && recordHeld.contains($0.id) }) {
            return false
        }
        if down {
            if case .key(53, _) = input, recorded.isEmpty {  // Escape
                swallowUntilReleased.insert(input.id)
                finishRecording(nil)
                return true
            }
            if !recorded.contains(where: { $0.id == input.id }) { recorded.append(input) }
            recordHeld.insert(input.id)
            live.pressed = recordHeld
            live.recording = recorded
            return true
        }
        recordHeld.remove(input.id)
        live.pressed = recordHeld
        guard recordHeld.isEmpty, !recorded.isEmpty else { return true }
        let trigger = Trigger(inputs: recorded)
        if !trigger.isValid {
            recorded = []
            live.recording = []
        } else {
            finishRecording(Trigger(inputs: recorded))
        }
        return true
    }

    private func finishRecording(_ trigger: Trigger?) {
        let recorder = recorder
        cancelRecording()
        live.pressed = []
        DispatchQueue.main.async { recorder?(trigger) }
    }

    // Another event tap, such as a dictation app listening to fn, can swallow a modifier's release before it
    // reaches this one. Modifiers are therefore read from each key and mouse event, which carries the live
    // flags, together with the hardware state, rather than from the history of flagsChanged events.
    private func syncModifiers(of trigger: Trigger, with event: CGEvent) {
        let live = event.flags.union(CGEventSource.flagsState(.hidSystemState))
        var changed = false
        for input in trigger.inputs {
            guard case .modifier(let code) = input, let flag = Input.modifierFlag(for: code) else { continue }
            if live.contains(flag) {
                changed = held.insert(input.id).inserted || changed
            } else {
                changed = held.remove(input.id) != nil || changed
            }
        }
        if changed { self.live.pressed = held }
    }

    private func resetState() {
        switch phase {
        case .dragging: end()
        case .arming: postKey(53, flags: [])  // Escape
        case .idle: break
        }
        phase = .idle
        held = []
        swallowUntilReleased = []
        live.pressed = []
    }

    private func physicallyHeld(_ trigger: Trigger) -> Bool {
        trigger.inputs.allSatisfy { input in
            switch input {
            case .mouseButton(let button):
                return CGMouseButton(rawValue: UInt32(button)).map { CGEventSource.buttonState(.hidSystemState, button: $0) } ?? false
            case .key(let code, _):
                return CGEventSource.keyState(.hidSystemState, key: CGKeyCode(code))
            case .modifier(let code):
                return Input.modifierFlag(for: code).map { CGEventSource.flagsState(.hidSystemState).contains($0) } ?? false
            }
        }
    }

    // Ends a capture whose release never arrived. Posted test events do not change the hardware state,
    // so the check waits until no trigger event has been seen for a second.
    private func startWatchdog() {
        watchdog?.invalidate()
        lastTriggerEvent = Date()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            guard phase != .idle, let trigger = preferences.trigger else { return timer.invalidate() }
            if Date().timeIntervalSince(lastTriggerEvent) > 1, !physicallyHeld(trigger) {
                resetState()
                timer.invalidate()
            }
        }
    }

    private func begin() {
        guard phase == .idle else { return }
        startWatchdog()
        phase = .arming
        releasedWhileArming = false
        pressScreenshotShortcut()

        // The crosshair ignores a press that arrives before screencaptureui is ready; 50 ms misses about half the time.
        let delay = Double(preferences.delayMs) / 1000
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard phase == .arming else { return }
            if releasedWhileArming {
                postKey(53, flags: [])  // Escape
                phase = .idle
            } else {
                postMouse(.leftMouseDown, at: pointerLocation())
                phase = .dragging
            }
        }
    }

    private func end() {
        switch phase {
        case .idle:
            break
        case .arming:
            releasedWhileArming = true
        case .dragging:
            postMouse(.leftMouseUp, at: pointerLocation())
            phase = .idle
            live.lastCapture = Date()
        }
    }

    private func pressScreenshotShortcut() {
        var flags: CGEventFlags = [.maskCommand, .maskShift]
        if preferences.target == .clipboard { flags.insert(.maskControl) }
        postKey(21, flags: flags)  // ANSI 4
    }

    private func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = flags
            post(event)
        }
    }

    private func postMouse(_ type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.flags = []
        post(event)
    }

    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    private func pointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}
