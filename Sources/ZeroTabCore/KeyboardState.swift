import Foundation

public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1)
    public static let option = Self(rawValue: 2)
    public static let shift = Self(rawValue: 4)
    public static let control = Self(rawValue: 8)
}

public enum InputAction: Equatable, Sendable {
    case begin(SwitchMode, backwards: Bool)
    case cycle(Int)
    case move(Direction)
    case commit
    case cancel
}

public struct InputDecision: Sendable {
    public var absorb: Bool
    public var action: InputAction?
    public init(_ absorb: Bool = false, _ action: InputAction? = nil) {
        self.absorb = absorb; self.action = action
    }
}

/// Pure input latch: release and cancel work even while presentation is still loading.
public struct KeyboardState: Sendable {
    public private(set) var mode: SwitchMode?
    private var cancelled = false
    private var capturedKeys = Set<UInt16>()
    public init() {}

    public mutating func reset() { self = Self() }

    public mutating func flagsChanged(_ modifiers: KeyModifiers) -> InputDecision {
        guard let mode else { return InputDecision() }
        let hold: KeyModifiers = mode == .applications ? .command : .option
        guard !modifiers.contains(hold) else { return InputDecision() }
        let shouldCommit = !cancelled
        self.mode = nil; cancelled = false
        return InputDecision(false, shouldCommit ? .commit : nil)
    }

    public mutating func keyUp(_ code: UInt16) -> InputDecision {
        InputDecision(capturedKeys.remove(code) != nil)
    }

    public mutating func keyDown(_ code: UInt16, modifiers: KeyModifiers, isRepeat: Bool) -> InputDecision {
        if mode == nil {
            guard code == 48, !isRepeat, !modifiers.contains(.control),
                  modifiers.contains(.command) != modifiers.contains(.option) else { return InputDecision() }
            let selected: SwitchMode = modifiers.contains(.command) ? .applications : .windows
            mode = selected; capturedKeys.insert(code)
            return InputDecision(true, .begin(selected, backwards: modifiers.contains(.shift)))
        }
        if cancelled {
            // Do not leak a second Tab into the original app before the held modifier is released.
            if code == 48 || code == 53 || (123...126).contains(code) {
                capturedKeys.insert(code); return InputDecision(true)
            }
            return InputDecision()
        }
        let action: InputAction?
        switch code {
        case 48: action = .cycle(modifiers.contains(.shift) ? -1 : 1)
        case 53: cancelled = true; action = .cancel
        case 123: action = .move(.left)
        case 124: action = .move(.right)
        case 125: action = .move(.down)
        case 126: action = .move(.up)
        default: return InputDecision()
        }
        capturedKeys.insert(code)
        return InputDecision(true, action)
    }
}
