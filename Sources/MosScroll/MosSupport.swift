//
//  MosSupport.swift
//  CtrlAlt — замена частей Mos, которые не переносились в CtrlAlt
//  (Options, KeyCode, Constants, RecordedEvent/ScrollHotkey, CGEvent+Extensions).
//  Основано на Mos by Caldis (https://github.com/Caldis/Mos), CC BY-NC 4.0.
//

import Cocoa

// MARK: - Настройки прокрутки (вместо Options.shared.scroll)

/// Настройки плавной прокрутки. Значения по умолчанию совпадают с Mos (OPTIONS_SCROLL_DEFAULT).
public struct MosScrollSettings: Codable, Equatable, Sendable {
    public var smooth = true
    public var smoothVertical = true
    public var smoothHorizontal = true
    public var reverse = true
    public var reverseVertical = true
    public var reverseHorizontal = true
    /// Минимальный шаг одного щелчка колеса.
    public var step = 33.6
    /// Множитель расстояния.
    public var speed = 2.70
    /// Длительность сглаживания, 1…5 (как ползунок в Mos).
    public var duration = 4.35
    public var deadZone = 1.00
    public var smoothSimTrackpad = false
    /// Клавиши-модификаторы (keyCode macOS) или nil.
    public var dash: UInt16? = MosKeyCode.optionL
    public var toggle: UInt16? = MosKeyCode.shiftL
    public var block: UInt16? = MosKeyCode.commandL
    /// CtrlAlt: вторая клавиша ускорения. Правый Command — это Alt внешней клавиатуры
    /// (Karabiner делает из него правый Command), поэтому Alt ускоряет прокрутку, как Option в Mos.
    public var dashAlternate: UInt16? = MosKeyCode.commandR

    public init() {}

    // Новые поля, которых нет в сохранённых настройках, получают значение по умолчанию.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MosScrollSettings()
        smooth = try c.decodeIfPresent(Bool.self, forKey: .smooth) ?? d.smooth
        smoothVertical = try c.decodeIfPresent(Bool.self, forKey: .smoothVertical) ?? d.smoothVertical
        smoothHorizontal = try c.decodeIfPresent(Bool.self, forKey: .smoothHorizontal) ?? d.smoothHorizontal
        reverse = try c.decodeIfPresent(Bool.self, forKey: .reverse) ?? d.reverse
        reverseVertical = try c.decodeIfPresent(Bool.self, forKey: .reverseVertical) ?? d.reverseVertical
        reverseHorizontal = try c.decodeIfPresent(Bool.self, forKey: .reverseHorizontal) ?? d.reverseHorizontal
        step = try c.decodeIfPresent(Double.self, forKey: .step) ?? d.step
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? d.duration
        deadZone = try c.decodeIfPresent(Double.self, forKey: .deadZone) ?? d.deadZone
        smoothSimTrackpad = try c.decodeIfPresent(Bool.self, forKey: .smoothSimTrackpad) ?? d.smoothSimTrackpad
        dash = c.contains(.dash) ? try c.decodeIfPresent(UInt16.self, forKey: .dash) : d.dash
        toggle = c.contains(.toggle) ? try c.decodeIfPresent(UInt16.self, forKey: .toggle) : d.toggle
        block = c.contains(.block) ? try c.decodeIfPresent(UInt16.self, forKey: .block) : d.block
        dashAlternate = c.contains(.dashAlternate) ? try c.decodeIfPresent(UInt16.self, forKey: .dashAlternate) : d.dashAlternate
    }

    /// Коэффициент интерполяции из длительности (формула Mos: generateDurationTransition).
    public var durationTransition: Double {
        let upperLimit = 5.0 + 0.2
        let val = 1 - (duration / upperLimit).squareRoot()
        return Double(round(1000 * val) / 1000)
    }

    /// Настройки из установленного Mos (com.caldis.Mos), если он был настроен.
    public static func importedFromMos(_ source: UserDefaults? = UserDefaults(suiteName: "com.caldis.Mos")) -> MosScrollSettings? {
        guard let defaults = source, defaults.object(forKey: "smooth") != nil else { return nil }
        var s = MosScrollSettings()
        func bool(_ key: String) -> Bool? { defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key) }
        func double(_ key: String) -> Double? {
            if let n = defaults.object(forKey: key) as? NSNumber { return n.doubleValue }
            if let t = defaults.string(forKey: key) { return Double(t) }
            return nil
        }
        // Горячие клавиши Mos хранит как JSON {"type":"keyboard","code":58}.
        func hotkey(_ key: String) -> UInt16?? {
            guard let data = defaults.data(forKey: key) else { return nil }
            struct Stored: Decodable { var type: String; var code: UInt16 }
            guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return .some(nil) }
            return .some(stored.type == "keyboard" ? stored.code : nil)
        }
        s.smooth = bool("smooth") ?? s.smooth
        s.smoothVertical = bool("smoothVertical") ?? s.smoothVertical
        s.smoothHorizontal = bool("smoothHorizontal") ?? s.smoothHorizontal
        s.reverse = bool("reverse") ?? s.reverse
        s.reverseVertical = bool("reverseVertical") ?? s.reverseVertical
        s.reverseHorizontal = bool("reverseHorizontal") ?? s.reverseHorizontal
        s.smoothSimTrackpad = bool("smoothSimTrackpad") ?? s.smoothSimTrackpad
        s.step = double("step") ?? s.step
        s.speed = double("speed") ?? s.speed
        s.duration = double("duration") ?? s.duration
        s.deadZone = double("deadZone") ?? s.deadZone
        if let v = hotkey("dash") { s.dash = v }
        if let v = hotkey("toggle") { s.toggle = v }
        if let v = hotkey("block") { s.block = v }
        return s
    }
}

// MARK: - Публичный вход для CtrlAlt

public enum MosScroll {
    /// Текущие настройки. Пишутся и читаются на главном потоке (обработчик прокрутки работает на главном run loop).
    nonisolated(unsafe) static var settings = MosScrollSettings()

    /// Применить настройки: действуют со следующего события прокрутки.
    public static func apply(_ newSettings: MosScrollSettings) {
        settings = newSettings
    }

    public static var isRunning: Bool { ScrollCore.shared.isActive }

    public static func start() { ScrollCore.shared.enable() }
    public static func stop() { ScrollCore.shared.disable() }

    /// Bundle ID настоящего Mos: если он запущен, CtrlAlt свою прокрутку не включает.
    public static let mosBundleID = "com.caldis.Mos"
}

// MARK: - Клавиши (вместо KeyCode и ScrollHotkey из Mos)

public enum MosKeyCode {
    public static let commandL: UInt16 = 55
    public static let commandR: UInt16 = 54
    public static let shiftL: UInt16 = 56
    public static let shiftR: UInt16 = 60
    public static let optionL: UInt16 = 58
    public static let optionR: UInt16 = 61
    public static let controlL: UInt16 = 59
    public static let controlR: UInt16 = 62
    public static let fn: UInt16 = 63

    /// Коды клавиш, которые считаются выбранной клавишей. Option, Shift и Control — с любой стороны,
    /// как в Windows и в привычке пользователя. Command — только выбранная сторона: правый Command
    /// в CtrlAlt — это Alt внешней клавиатуры, а левый — Win и Command MacBook.
    public static func matchingCodes(for code: UInt16) -> [UInt16] {
        switch code {
        case optionL, optionR: return [optionL, optionR]
        case shiftL, shiftR: return [shiftL, shiftR]
        case controlL, controlR: return [controlL, controlR]
        default: return [code]
        }
    }

    static func mask(for code: UInt16) -> CGEventFlags {
        switch code {
        case commandL, commandR: return .maskCommand
        case shiftL, shiftR: return .maskShift
        case optionL, optionR: return .maskAlternate
        case controlL, controlR: return .maskControl
        case fn: return .maskSecondaryFn
        default: return CGEventFlags(rawValue: 0)
        }
    }
}

/// Горячая клавиша прокрутки (в CtrlAlt — только клавиатура).
struct ScrollHotkey: Equatable {
    enum Kind { case keyboard, mouse }
    let type: Kind
    let code: UInt16

    var isModifierKey: Bool { type == .keyboard && MosKeyCode.mask(for: code).rawValue != 0 }
    var modifierMask: CGEventFlags { MosKeyCode.mask(for: code) }

    func matches(_ event: CGEvent, keyCode: UInt16, mouseButton: UInt16, isMouseEvent: Bool) -> Bool {
        switch type {
        case .keyboard: return !isMouseEvent && code == keyCode
        case .mouse: return isMouseEvent && code == mouseButton
        }
    }
}

extension CGEvent {
    var keyCode: UInt16 { UInt16(getIntegerValueField(.keyboardEventKeycode)) }

    var isKeyDown: Bool {
        if type == .flagsChanged { return flags.contains(MosKeyCode.mask(for: keyCode)) }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown { return true }
        return type == .keyDown
    }

    var isKeyUp: Bool { !isKeyDown }
}

// MARK: - Константы (из Mos/Utils/Constants.swift)

struct SPECIAL_EVENT_SOURCE_APPLICATION {
    static let logitechOptions = "com.logitech.manager.daemon"
}

struct REMOTE_CONTROL_APPLICATION {
    static let executableKeywords = [
        "screensharingd",
        "ScreensharingAgent",
        "ARDAgent",
    ]
    static let bundleIdentifiers = [
        "com.teamviewer.TeamViewer",
        "com.teamviewer.TeamViewerHost",
        "com.anydesk.anydesk",
        "com.parsec.www",
        "com.rustdesk.RustDesk",
        "com.microsoft.rdc.macos",
        "com.realvnc.vncviewer",
        "com.tigervnc.vncviewer",
        "com.netease.uuremote",
    ]
}

extension Notification.Name {
    static let mosAccessibilityPermissionLost = Notification.Name("CtrlAltMosScrollAccessibilityPermissionLost")
}
