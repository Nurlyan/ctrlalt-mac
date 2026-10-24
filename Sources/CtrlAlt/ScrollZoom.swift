import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Ctrl + колесо мыши → Command+= / Command+- (масштаб), как в Windows.
///
/// Колесо Karabiner не обрабатывает, поэтому здесь event tap на уровне HID: он видит прокрутку
/// раньше Mos и забирает только Ctrl+колесо, остальная прокрутка идёт в Mos как обычно.
/// Флаги CGEvent не говорят, с какой клавиатуры нажат Ctrl, поэтому Ctrl встроенной клавиатуры
/// тоже сработает (сам по себе Ctrl+колесо в macOS ничего не делает).
@MainActor
final class ScrollZoom {
    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        // Значение kAXTrustedCheckOptionPrompt; сама константа не concurrency-safe в Swift 6.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    var isRunning: Bool { zoomTap != nil }

    /// Возвращает false, если tap не создан (обычно нет разрешения «Универсальный доступ»).
    @discardableResult
    func start() -> Bool {
        if zoomTap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollZoomCallback,
            userInfo: nil
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        zoomTap = tap
        zoomSource = source
        return true
    }

    func stop() {
        guard let tap = zoomTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = zoomSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        zoomTap = nil
        zoomSource = nil
    }
}

// Callback вызывается на главном run loop; глобальные переменные нужны C-функции обратного вызова.
nonisolated(unsafe) private var zoomTap: CFMachPort?
nonisolated(unsafe) private var zoomSource: CFRunLoopSource?

private func scrollZoomCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = zoomTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

    // Только Ctrl (Shift допускается), без Command и Option.
    let flags = event.flags
    guard flags.contains(.maskControl), !flags.contains(.maskCommand), !flags.contains(.maskAlternate) else {
        return Unmanaged.passUnretained(event)
    }
    // Только колесо мыши: у трекпада есть щипок, его прокрутку не трогаем.
    guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else {
        return Unmanaged.passUnretained(event)
    }
    let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    guard delta != 0 else { return Unmanaged.passUnretained(event) }

    // Направление физического колеса, независимо от «естественной прокрутки» и Mos.
    let inverted = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false
    let wheelAway = inverted ? delta < 0 : delta > 0
    postCommandKey(wheelAway ? kVK_ANSI_Equal : kVK_ANSI_Minus)
    return nil
}

private func postCommandKey(_ keyCode: Int) {
    let source = CGEventSource(stateID: .privateState)
    for down in [true, false] {
        guard let key = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down) else { continue }
        key.flags = .maskCommand
        key.post(tap: .cghidEventTap)
    }
}
