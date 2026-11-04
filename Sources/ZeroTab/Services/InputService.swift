import AppKit
import ZeroTabCore
import OSLog

final class InputService: @unchecked Sendable {
    private var tap: CFMachPort?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private let lock = NSLock()
    private var keyboard = KeyboardState()
    private var enabled = false
    private var generation: UInt64 = 0
    private let logger = Logger(subsystem: "dev.hitomeng.ZeroTab", category: "Input")
    var onAction: ((InputAction) -> Void)?
    var onInterrupted: (() -> Void)?

    func start() -> Bool {
        if tap != nil { return true }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<InputService>.fromOpaque(context).takeUnretainedValue().handle(type, event)
        }
        guard let created = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = created
        lock.lock(); enabled = true; keyboard.reset(); generation &+= 1; let token = generation; lock.unlock()
        let worker = Thread { [weak self] in
            guard let self else { return }
            let loop = CFRunLoopGetCurrent()!
            let source = CFMachPortCreateRunLoopSource(nil, created, 0)!
            self.lock.lock()
            let shouldRun = self.enabled && self.generation == token
            if shouldRun { self.runLoop = loop }
            self.lock.unlock()
            guard shouldRun else { return }
            CFRunLoopAddSource(loop, source, .commonModes)
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        worker.name = "ZeroTab Input"
        worker.qualityOfService = .userInteractive
        thread = worker; worker.start()
        return true
    }

    func stop() {
        lock.lock(); enabled = false; generation &+= 1; keyboard.reset(); let loop = runLoop; runLoop = nil; lock.unlock()
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        if let loop { CFRunLoopStop(loop) }
        thread = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock(); keyboard.reset(); let active = enabled; lock.unlock()
            if active, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            DispatchQueue.main.async { [weak self] in self?.onInterrupted?() }
            return Unmanaged.passUnretained(event)
        }
        var modifiers: KeyModifiers = []
        if event.flags.contains(.maskCommand) { modifiers.insert(.command) }
        if event.flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if event.flags.contains(.maskShift) { modifiers.insert(.shift) }
        if event.flags.contains(.maskControl) { modifiers.insert(.control) }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        lock.lock()
        guard enabled else { lock.unlock(); return Unmanaged.passUnretained(event) }
        let decision: InputDecision
        switch type {
        case .flagsChanged: decision = keyboard.flagsChanged(modifiers)
        case .keyDown: decision = keyboard.keyDown(code, modifiers: modifiers,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp: decision = keyboard.keyUp(code)
        default: decision = InputDecision()
        }
        lock.unlock()
        if let action = decision.action {
            if case .begin(let mode, _) = action { logger.info("Shortcut received: \(mode.rawValue, privacy: .public)") }
            DispatchQueue.main.async { [weak self] in self?.onAction?(action) }
        }
        return decision.absorb ? nil : Unmanaged.passUnretained(event)
    }

    deinit { stop() }
}
