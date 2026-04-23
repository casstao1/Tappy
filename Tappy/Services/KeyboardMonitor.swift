import AppKit
import CoreGraphics
import Foundation

struct KeyboardTrigger {
    let category: SoundCategory
    let keyCode: UInt16
}

final class KeyboardMonitor {
    enum CaptureState: Equatable {
        case stopped
        case ready
        case unavailable
    }

    private let duplicateSuppressionWindow: TimeInterval = 0.035

    private var localKeyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var appDidBecomeActiveObserver: Any?
    private var appDidResignActiveObserver: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var eventTapThread: Thread?
    private var eventTapRunLoop: CFRunLoop?

    private var handler: ((KeyboardTrigger) -> Void)?
    private var lastTriggerKeyCode: UInt16?
    private var lastTriggerTime: TimeInterval = 0
    private var isAppActive = false

    private(set) var isMonitoring = false
    private(set) var captureState: CaptureState = .stopped

    var onCaptureStateChange: ((CaptureState) -> Void)?

    func start(handler: @escaping (KeyboardTrigger) -> Void) {
        stop()
        self.handler = handler
        installApplicationActivityObservers()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.processKeyDown(event)
            return event
        }

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.processFlagsChanged(event)
            return event
        }

        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.processKeyUp(event)
            return event
        }

        startEventTap()

        isMonitoring = true
    }

    func stop() {
        removeMonitor(localKeyMonitor)
        removeMonitor(localFlagsMonitor)
        removeMonitor(localKeyUpMonitor)
        removeApplicationActivityObservers()
        localKeyMonitor = nil
        localFlagsMonitor = nil
        localKeyUpMonitor = nil
        stopEventTap()
        handler = nil
        isMonitoring = false
        updateCaptureState(.stopped)
    }

    private func removeMonitor(_ monitor: Any?) {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
    }

    private func installApplicationActivityObservers() {
        isAppActive = NSApp.isActive

        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAppActive = true
        }

        appDidResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAppActive = false
        }
    }

    private func removeApplicationActivityObservers() {
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = appDidResignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        appDidBecomeActiveObserver = nil
        appDidResignActiveObserver = nil
        isAppActive = false
    }

    private func processKeyDown(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let trigger = triggerForKeyCode(event.keyCode)
        emit(trigger)
    }

    private func processKeyUp(_ event: NSEvent) {
        _ = event
    }

    private func processFlagsChanged(_ event: NSEvent) {
        guard isModifierPress(event) else { return }
        emit(.modifier, keyCode: event.keyCode)
    }

    private func startEventTap() {
        // Preflight: refuse to claim "ready" if macOS hasn't actually granted
        // Input Monitoring to this running process. Without this guard we'd
        // flip into .ready on a zombie tap and mislead the diagnostics UI.
        guard CGPreflightListenEventAccess() else {
            updateCaptureState(.unavailable)
            return
        }

        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.keyUp.rawValue) |
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleEventTap(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            updateCaptureState(.unavailable)
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        eventTapSource = source

        // Enable the tap synchronously here so the subsequent
        // `tapIsEnabled` check reflects the truth. Doing it inside the
        // worker thread (as we used to) created a race where we reported
        // "unavailable" before the thread had a chance to enable the tap.
        CGEvent.tapEnable(tap: tap, enable: true)

        guard CGEvent.tapIsEnabled(tap: tap) else {
            // macOS created the tap but immediately disabled it — almost
            // always means permission hasn't fully taken effect for this
            // running process and a relaunch is required.
            stopEventTap()
            updateCaptureState(.unavailable)
            return
        }

        let thread = Thread { [weak self] in
            guard let self else { return }

            let runLoop = CFRunLoopGetCurrent()
            self.eventTapRunLoop = runLoop
            CFRunLoopAddSource(runLoop, source, CFRunLoopMode.commonModes)

            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.5, true)
            }

            CFRunLoopRemoveSource(runLoop, source, CFRunLoopMode.commonModes)
        }
        thread.name = "Tappy.KeyboardEventTap"
        eventTapThread = thread
        thread.start()

        updateCaptureState(.ready)
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let runLoop = eventTapRunLoop {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }

        eventTapThread?.cancel()
        eventTapThread = nil
        eventTapRunLoop = nil
        eventTapSource = nil
        eventTap = nil
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if isAppActive {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            let keyCodeValue = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard !isRepeat else {
                return Unmanaged.passUnretained(event)
            }
            let trigger = triggerForKeyCode(keyCodeValue)
            emit(trigger)
        case .keyUp:
            break
        case .flagsChanged:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            guard isModifierPress(keyCode: keyCode, modifierFlags: flags) else {
                return Unmanaged.passUnretained(event)
            }
            emit(.modifier, keyCode: keyCode)
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func processKeyCode(_ keyCode: CGKeyCode, isModifier: Bool) {
        if isModifier {
            switch keyCode {
            case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
                emit(.modifier, keyCode: UInt16(keyCode))
            default:
                break
            }
            return
        }

        emit(triggerForKeyCode(UInt16(keyCode)))
    }

    private func emit(_ category: SoundCategory, keyCode: UInt16) {
        emit(KeyboardTrigger(category: category, keyCode: keyCode))
    }

    private func emit(_ trigger: KeyboardTrigger, bypassSuppression: Bool = false) {
        if bypassSuppression || trigger.category == .delete {
            handler?(trigger)
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if lastTriggerKeyCode == trigger.keyCode, now - lastTriggerTime < duplicateSuppressionWindow {
            return
        }

        lastTriggerKeyCode = trigger.keyCode
        lastTriggerTime = now
        handler?(trigger)
    }

    private func isModifierPress(_ event: NSEvent) -> Bool {
        isModifierPress(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }

    private func isModifierPress(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 54, 55:
            return modifierFlags.contains(.command)
        case 56, 60:
            return modifierFlags.contains(.shift)
        case 58, 61:
            return modifierFlags.contains(.option)
        case 59, 62:
            return modifierFlags.contains(.control)
        case 57:
            return modifierFlags.contains(.capsLock)
        case 63:
            return modifierFlags.contains(.function)
        default:
            return false
        }
    }

    private func updateCaptureState(_ newState: CaptureState) {
        guard captureState != newState else { return }
        captureState = newState
        DispatchQueue.main.async { [weak self] in
            self?.onCaptureStateChange?(newState)
        }
    }

    private func triggerForKeyCode(_ keyCode: UInt16) -> KeyboardTrigger {
        switch keyCode {
        case 49:
            return KeyboardTrigger(category: .space, keyCode: keyCode)
        case 36, 76:
            return KeyboardTrigger(category: .returnKey, keyCode: keyCode)
        case 51, 117:
            return KeyboardTrigger(category: .delete, keyCode: keyCode)
        default:
            return KeyboardTrigger(category: .standard, keyCode: keyCode)
        }
    }

}
