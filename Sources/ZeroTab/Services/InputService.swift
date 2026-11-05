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

    // Lifecycle entry points run on the main thread. The event callback and
    // worker use the lock for every shared tap, keyboard and generation access.
    func start() -> Bool {
        lock.lock()
        let healthy = enabled && tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } == true
        let replacing = tap != nil
        lock.unlock()
        if healthy { return true }
        stop()
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<InputService>.fromOpaque(context).takeUnretainedValue().handle(type, event)
        }
        guard let created = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            logger.error("Unable to create keyboard event tap")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(nil, created, 0),
              CFMachPortIsValid(created), CGEvent.tapIsEnabled(tap: created) else {
            CFMachPortInvalidate(created)
            logger.error("Keyboard event tap is not usable")
            return false
        }
        lock.lock(); tap = created; enabled = true; keyboard.reset(); generation &+= 1; let token = generation; lock.unlock()
        // Queue cancellation before the replacement worker can deliver input.
        if replacing { notifyInterruption(generation: token) }
        let worker = Thread { [weak self] in
            guard let self else { return }
            let loop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(loop, source, .commonModes)
            self.lock.lock()
            let shouldRun = self.enabled && self.generation == token
            if shouldRun { self.runLoop = loop }
            self.lock.unlock()
            if shouldRun { CFRunLoopRun() }
            CFRunLoopRemoveSource(loop, source, .commonModes)
            self.lock.lock()
            let unexpectedExit = self.enabled && self.generation == token
            if unexpectedExit { self.enabled = false; self.runLoop = nil }
            self.lock.unlock()
            if unexpectedExit {
                self.logger.error("Keyboard event run loop exited unexpectedly")
                self.notifyInterruption(generation: token)
            }
        }
        worker.name = "ZeroTab Input"
        worker.qualityOfService = .userInteractive
        thread = worker; worker.start()
        logger.info("Keyboard event tap started; replaced=\(replacing)")
        return true
    }

    func stop() {
        lock.lock()
        enabled = false; generation &+= 1; keyboard.reset()
        let loop = runLoop; runLoop = nil
        let previousTap = tap; tap = nil
        lock.unlock()
        if let previousTap { CFMachPortInvalidate(previousTap) }
        if let loop {
            // A direct stop before CFRunLoopRun starts can be lost. A queued
            // block also covers stop/restart during worker startup.
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
            CFRunLoopWakeUp(loop)
        }
        thread = nil
    }

    private func notifyInterruption(generation token: UInt64) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let current = self.generation == token; self.lock.unlock()
            guard current else { return }
            self.onInterrupted?()
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            keyboard.reset()
            let active = enabled
            let token = generation
            if active, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            let recovered = active && tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } == true
            lock.unlock()
            logger.notice("Keyboard event tap disabled; timeout=\(type == .tapDisabledByTimeout), reenabled=\(recovered)")
            if active { notifyInterruption(generation: token) }
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
        let token = generation
        lock.unlock()
        if let action = decision.action {
            if case .begin(let mode, _) = action { logger.info("Shortcut received: \(mode.rawValue, privacy: .public)") }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock(); let current = self.enabled && self.generation == token; self.lock.unlock()
                guard current else { return }
                self.onAction?(action)
            }
        }
        return decision.absorb ? nil : Unmanaged.passUnretained(event)
    }

    deinit { stop() }
}
