import Foundation

public typealias JSONObject = [String: Any]

/// Модель клавиатуры по VID/PID. Это модель, а не конкретный экземпляр устройства.
public struct KeyboardID: Hashable, Codable, Sendable {
    public var vendorID: Int
    public var productID: Int

    public init(vendorID: Int, productID: Int) {
        self.vendorID = vendorID
        self.productID = productID
    }

    public var hex: String { String(format: "%04x:%04x", vendorID, productID) }
}

/// Включаемые группы Windows-сочетаний.
public struct Features: Codable, Equatable, Sendable {
    /// Удерживаемый Alt+Tab через стандартный переключатель macOS.
    public var altTab = true
    /// Левый Alt + левый Shift (и правые) без третьей клавиши меняют раскладку.
    public var altShiftLayout = true
    /// Win+Space меняет раскладку.
    public var winSpaceLayout = true
    /// Одиночный Win открывает Spotlight.
    public var winAloneSpotlight = true
    /// Ctrl+буква → Command+буква (кроме терминалов), Ctrl+Y — повтор.
    public var ctrlShortcuts = true
    /// Ctrl+стрелки и Ctrl+Backspace/Delete работают по словам.
    public var ctrlWordNavigation = true
    /// Home/End — начало и конец строки.
    public var homeEnd = true
    /// Win+Ctrl+←/→ — соседний рабочий стол (системные Ctrl+←/→), как в Windows.
    public var winCtrlDesktops = true

    public init() {}

    // Новые группы, которых нет в сохранённых настройках, получают значение по умолчанию.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Features()
        altTab = try c.decodeIfPresent(Bool.self, forKey: .altTab) ?? d.altTab
        altShiftLayout = try c.decodeIfPresent(Bool.self, forKey: .altShiftLayout) ?? d.altShiftLayout
        winSpaceLayout = try c.decodeIfPresent(Bool.self, forKey: .winSpaceLayout) ?? d.winSpaceLayout
        winAloneSpotlight = try c.decodeIfPresent(Bool.self, forKey: .winAloneSpotlight) ?? d.winAloneSpotlight
        ctrlShortcuts = try c.decodeIfPresent(Bool.self, forKey: .ctrlShortcuts) ?? d.ctrlShortcuts
        ctrlWordNavigation = try c.decodeIfPresent(Bool.self, forKey: .ctrlWordNavigation) ?? d.ctrlWordNavigation
        homeEnd = try c.decodeIfPresent(Bool.self, forKey: .homeEnd) ?? d.homeEnd
        winCtrlDesktops = try c.decodeIfPresent(Bool.self, forKey: .winCtrlDesktops) ?? d.winCtrlDesktops
    }
}

/// Генерирует complex modifications Karabiner для выбранных клавиатур.
///
/// Правила повторяют набор, проверенный вручную на KD83A (см. Tests/…/Fixtures).
public enum RuleGenerator {
    public static let descriptionPrefix = "CtrlAlt"

    public static let altHeld = "ctrlalt_alt_held"
    /// Во что превращается левый Alt: правый Command. Для macOS это обычный Command (Alt+Tab работает),
    /// но его можно отличить от Win (левый Command) — например, для быстрой прокрутки.
    public static let altCommand = "right_command"
    static let switcherActive = "ctrlalt_alt_tab_active"

    static let terminals = [
        "^com\\.apple\\.Terminal$",
        "^com\\.googlecode\\.iterm2$",
        "^com\\.mitchellh\\.ghostty$",
        "^net\\.kovidgoyal\\.kitty$",
        "^io\\.alacritty$",
        "^com\\.github\\.wez\\.wezterm$",
        "^dev\\.warp\\.Warp-Stable$",
    ]
    /// Приложения, где Ctrl+Shift+C/V копирует и вставляет.
    static let shiftCopyPasteApps = terminals + ["^com\\.microsoft\\.VSCode(?:Insiders)?$"]

    /// Клавиши, которые с левым Alt (вне переключателя) дают Option+клавиша.
    /// F-клавиши не трогаем, чтобы не мешать их настройке в Karabiner.
    static let backToOption: [String] =
        "abcdefghijklmnopqrstuvwxyz".map(String.init)
        + (0...9).map(String.init)
        + [
            "hyphen", "equal_sign", "open_bracket", "close_bracket", "backslash",
            "semicolon", "quote", "comma", "period", "slash", "grave_accent_and_tilde",
            "return_or_enter", "delete_or_backspace", "delete_forward", "spacebar", "escape",
            "left_arrow", "right_arrow", "up_arrow", "down_arrow",
            "home", "end", "page_up", "page_down",
        ]

    static var switchLayout: JSONObject { ["key_code": "spacebar", "modifiers": ["left_control"]] }
    static var aloneTimeout: JSONObject { ["basic.to_if_alone_timeout_milliseconds": 1000] }

    public static func rules(for keyboards: [KeyboardID], features: Features) -> [JSONObject] {
        guard !keyboards.isEmpty else { return [] }
        let device: JSONObject = [
            "type": "device_if",
            "identifiers": keyboards.map { ["vendor_id": $0.vendorID, "product_id": $0.productID, "is_keyboard": true] },
        ]
        let ids = keyboards.map(\.hex).joined(separator: ", ")

        var result: [JSONObject] = []
        let altWin = altAndWinManipulators(device: device, features: features)
        if !altWin.isEmpty {
            result.append(["description": "\(descriptionPrefix) — Alt и Win (\(ids))", "manipulators": altWin])
        }
        let ctrl = ctrlManipulators(device: device, features: features)
        if !ctrl.isEmpty {
            result.append(["description": "\(descriptionPrefix) — Ctrl-сочетания, Home/End (\(ids))", "manipulators": ctrl])
        }
        return result
    }

    // MARK: - Alt и Win

    static func altAndWinManipulators(device: JSONObject, features: Features) -> [JSONObject] {
        var m: [JSONObject] = []

        if features.altTab {
            if features.altShiftLayout {
                // Shift↓ затем Alt↓: Alt держит Command (для Shift+Alt+Tab),
                // отпускание Alt без третьей клавиши меняет раскладку.
                m.append([
                    "type": "basic",
                    "from": ["key_code": "left_option", "modifiers": ["mandatory": ["left_shift"], "optional": ["caps_lock"]]],
                    "to": [setVar(altHeld, 1), ["key_code": altCommand, "modifiers": ["left_shift"]]],
                    "to_if_alone": [switchLayout],
                    "to_after_key_up": [setVar(altHeld, 0), setVar(switcherActive, 0)],
                    "conditions": [device],
                    "parameters": aloneTimeout,
                ])
                // Alt↓ затем Shift↓: отпускание Shift без третьей клавиши меняет раскладку.
                // В открытом переключателе Shift работает как обычно (обратный проход).
                m.append([
                    "type": "basic",
                    "from": ["key_code": "left_shift", "modifiers": ["mandatory": [altCommand], "optional": ["caps_lock"]]],
                    "to": [["key_code": "left_shift", "modifiers": [altCommand]]],
                    "to_if_alone": [switchLayout],
                    "conditions": [device, varIf(altHeld, 1), varIf(switcherActive, 0)],
                    "parameters": aloneTimeout,
                ])
            }
            // Tab при удержанном Alt: Command уже зажат, отмечаем открытый переключатель.
            m.append([
                "type": "basic",
                "from": ["key_code": "tab", "modifiers": ["optional": ["any"]]],
                "to": [setVar(switcherActive, 1), ["key_code": "tab"]],
                "conditions": [device, varIf(altHeld, 1)],
            ])
            // Левый Alt держит Command (правый, см. altCommand) до отпускания.
            m.append([
                "type": "basic",
                "from": ["key_code": "left_option", "modifiers": ["optional": ["any"]]],
                "to": [setVar(altHeld, 1), ["key_code": altCommand]],
                "to_after_key_up": [setVar(altHeld, 0), setVar(switcherActive, 0)],
                "conditions": [device],
            ])
            // Alt+клавиша вне переключателя → Option+клавиша.
            for key in backToOption {
                m.append([
                    "type": "basic",
                    "from": ["key_code": key, "modifiers": ["mandatory": [altCommand], "optional": ["any"]]],
                    "to": [["key_code": key, "modifiers": ["left_option"]]],
                    "conditions": [device, varIf(altHeld, 1), varIf(switcherActive, 0)],
                ])
            }
        } else if features.altShiftLayout {
            // Без Alt+Tab левый Alt остаётся Option.
            m.append(optionShiftLayout(from: "left_shift", mandatory: "option", to: "left_shift", with: "left_option", device: device))
            m.append(optionShiftLayout(from: "left_option", mandatory: "shift", to: "left_option", with: "left_shift", device: device))
        }

        if features.winSpaceLayout {
            // Win+Space → смена раскладки, один раз на нажатие без автоповтора.
            var switchOnce = switchLayout
            switchOnce["repeat"] = false
            m.append([
                "type": "basic",
                "from": ["key_code": "spacebar", "modifiers": ["mandatory": ["left_command"], "optional": ["caps_lock"]]],
                "to": [switchOnce],
                "conditions": features.altTab ? [device, varIf(altHeld, 0)] : [device],
            ])
        }

        if features.winAloneSpotlight {
            // Одиночный Win → Spotlight; с другими клавишами Win остаётся Command.
            m.append([
                "type": "basic",
                "from": ["key_code": "left_command", "modifiers": ["optional": ["any"]]],
                "to": [["key_code": "left_command"]],
                "to_if_alone": [["key_code": "spacebar", "modifiers": ["left_command"]]],
                "conditions": [device],
                "parameters": aloneTimeout,
            ])
        }

        if features.winCtrlDesktops {
            // Win+Ctrl+←/→ → Ctrl+←/→: соседний рабочий стол. Обычный Ctrl+←/→ остаётся «по словам».
            for key in ["left_arrow", "right_arrow"] {
                m.append([
                    "type": "basic",
                    "from": ["key_code": key, "modifiers": ["mandatory": ["left_command", "control"], "optional": ["caps_lock"]]],
                    "to": [["key_code": key, "modifiers": ["left_control"]]],
                    "conditions": features.altTab ? [device, varIf(altHeld, 0)] : [device],
                ])
            }
        }
        return m
    }

    // MARK: - Ctrl, Home/End

    static func ctrlManipulators(device: JSONObject, features: Features) -> [JSONObject] {
        var m: [JSONObject] = []
        let outsideTerminals: JSONObject = ["type": "frontmost_application_unless", "bundle_identifiers": terminals]

        if features.altShiftLayout {
            // Правый Alt остаётся Option, поэтому правая пара работает по-старому.
            m.append(optionShiftLayout(from: "right_shift", mandatory: "option", to: "right_shift", with: "left_option", device: device))
            m.append(optionShiftLayout(from: "right_option", mandatory: "shift", to: "right_option", with: "left_shift", device: device))
        }

        if features.ctrlShortcuts {
            // В терминалах и VS Code Ctrl+Shift+C/V копирует и вставляет.
            let inShiftCopyPasteApps: JSONObject = ["type": "frontmost_application_if", "bundle_identifiers": shiftCopyPasteApps]
            for key in ["c", "v"] {
                m.append(remap(key, ["control", "shift"], to: key, ["left_command"], conditions: [device, inShiftCopyPasteApps]))
            }
            for key in "abcdefghijklmnopqrstuvwxyz".map(String.init) {
                switch key {
                case "q", "h", "m":
                    // Command+Q/H/M закрывает, скрывает и сворачивает — оставляем обычный Ctrl.
                    break
                case "y":
                    m.append(remap("y", ["control"], to: "z", ["left_command", "left_shift"], conditions: [device, outsideTerminals]))
                case "c":
                    // В VS Code Ctrl+C тоже остаётся Ctrl (прерывание во встроенном терминале).
                    let outsideShiftCopyPasteApps: JSONObject = ["type": "frontmost_application_unless", "bundle_identifiers": shiftCopyPasteApps]
                    m.append(remap("c", ["control"], to: "c", ["left_command"], conditions: [device, outsideShiftCopyPasteApps]))
                default:
                    m.append(remap(key, ["control"], to: key, ["left_command"], conditions: [device, outsideTerminals]))
                }
                // Command+Shift+Q — выход из учётной записи.
                if key != "q" {
                    m.append(remap(key, ["control", "shift"], to: key, ["left_command", "left_shift"], conditions: [device, outsideTerminals]))
                }
            }
        }

        if features.ctrlWordNavigation {
            let keys = ["left_arrow", "right_arrow", "delete_or_backspace", "delete_forward"]
            for key in keys {
                m.append(remap(key, ["control"], to: key, ["left_option"], conditions: [device, outsideTerminals]))
            }
            for key in keys {
                m.append(remap(key, ["control", "shift"], to: key, ["left_option", "left_shift"], conditions: [device, outsideTerminals]))
            }
        }

        if features.homeEnd {
            m.append(remap("home", [], to: "left_arrow", ["left_command"], conditions: [device, outsideTerminals]))
            m.append(remap("end", [], to: "right_arrow", ["left_command"], conditions: [device, outsideTerminals]))
        }
        return m
    }

    // MARK: - Помощники

    static func setVar(_ name: String, _ value: Int) -> JSONObject {
        ["set_variable": ["name": name, "value": value]]
    }

    static func varIf(_ name: String, _ value: Int) -> JSONObject {
        ["type": "variable_if", "name": name, "value": value]
    }

    static func remap(_ key: String, _ mandatory: [String], to toKey: String, _ toModifiers: [String], conditions: [JSONObject]) -> JSONObject {
        [
            "type": "basic",
            "from": ["key_code": key, "modifiers": ["mandatory": mandatory, "optional": ["caps_lock"]]],
            "to": [["key_code": toKey, "modifiers": toModifiers]],
            "conditions": conditions,
        ]
    }

    /// Alt+Shift без третьей клавиши → Ctrl+Space, когда Alt работает как Option.
    static func optionShiftLayout(from key: String, mandatory: String, to toKey: String, with modifier: String, device: JSONObject) -> JSONObject {
        [
            "type": "basic",
            "from": ["key_code": key, "modifiers": ["mandatory": [mandatory], "optional": ["caps_lock"]]],
            "to": [["key_code": toKey, "modifiers": [modifier], "lazy": true]],
            "conditions": [device],
            "to_if_alone": [switchLayout],
            "parameters": aloneTimeout,
        ]
    }
}
