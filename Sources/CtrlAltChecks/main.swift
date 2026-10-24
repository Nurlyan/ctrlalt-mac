// Проверки логики без XCTest/Swift Testing (их макросов нет в Command Line Tools).
// Запуск: swift run CtrlAltChecks
import CtrlAltCore
import Foundation
import MosScroll

var failures = 0
var current = ""

@MainActor func check(_ condition: Bool, _ message: @autoclosure () -> String = "") {
    if !condition {
        failures += 1
        print("  ✘ \(current): \(message())")
    }
}

@MainActor func test(_ name: String, _ body: () throws -> Void) {
    current = name
    let before = failures
    do { try body() } catch { check(false, "исключение: \(error)") }
    print(failures == before ? "✔ \(name)" : "✘ \(name)")
}

let kd83a = KeyboardID(vendorID: 0x0416, productID: 0x7472)

func manipulators(_ rule: JSONObject) -> [NSDictionary] {
    (rule["manipulators"] as? [JSONObject] ?? []).map { NSDictionary(dictionary: $0) }
}

func features(mask: Int) -> Features {
    var f = Features()
    f.altTab = mask & 1 != 0; f.altShiftLayout = mask & 2 != 0; f.winSpaceLayout = mask & 4 != 0
    f.winAloneSpotlight = mask & 8 != 0; f.ctrlShortcuts = mask & 16 != 0
    f.ctrlWordNavigation = mask & 32 != 0; f.homeEnd = mask & 64 != 0; f.winCtrlDesktops = mask & 128 != 0
    return f
}

// MARK: - Генератор правил

test("правила совпадают с проверенными на KD83A") {
    // Файл, проверенный вручную на клавиатуре; переменные приведены к именам приложения.
    let url = Bundle.module.url(forResource: "kd83a-verified", withExtension: "json", subdirectory: "Fixtures")!
    let text = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\"kd83a_", with: "\"ctrlalt_")
    let expected = (try JSONSerialization.jsonObject(with: Data(text.utf8)) as! JSONObject)["rules"] as! [JSONObject]

    // Win+Ctrl+←/→ добавлен после ручной проверки.
    var f = Features()
    f.winCtrlDesktops = false
    let generated = RuleGenerator.rules(for: [kd83a], features: f)
    check(generated.count == expected.count, "правил \(generated.count), ожидалось \(expected.count)")
    for (gen, exp) in zip(generated, expected) {
        let g = manipulators(gen), e = manipulators(exp)
        check(g.count == e.count, "манипуляторов \(g.count), ожидалось \(e.count)")
        for (index, (a, b)) in zip(g, e).enumerated() where !a.isEqual(b) {
            check(false, "манипулятор \(index) в «\(gen["description"] ?? "")» отличается")
        }
    }
}

test("Win+Ctrl+←/→ переключает рабочие столы") {
    let altWin = RuleGenerator.rules(for: [kd83a], features: Features())[0]["manipulators"] as! [JSONObject]
    for m in altWin.suffix(2) {
        let from = m["from"] as! JSONObject
        let to = (m["to"] as! [JSONObject])[0]
        check(["left_arrow", "right_arrow"].contains(from["key_code"] as! String))
        check((from["modifiers"] as! JSONObject)["mandatory"] as! [String] == ["left_command", "control"])
        check(to["modifiers"] as! [String] == ["left_control"])
    }
}

test("старые настройки без новой группы читаются") {
    let old = #"{"altTab":false,"altShiftLayout":true,"winSpaceLayout":true,"winAloneSpotlight":true,"ctrlShortcuts":true,"ctrlWordNavigation":true,"homeEnd":true}"#
    let f = try JSONDecoder().decode(Features.self, from: Data(old.utf8))
    check(f.altTab == false)
    check(f.winCtrlDesktops == true)
}

test("без клавиатуры и без групп правил нет") {
    check(RuleGenerator.rules(for: [], features: Features()).isEmpty)
    check(RuleGenerator.rules(for: [kd83a], features: features(mask: 0)).isEmpty)
}

test("Alt+Shift без Alt+Tab оставляет Alt как Option") {
    var f = Features()
    f.altTab = false
    let rules = RuleGenerator.rules(for: [kd83a], features: f)
    let json = String(decoding: try JSONSerialization.data(withJSONObject: rules), as: UTF8.self)
    check(!json.contains(RuleGenerator.altHeld))
    let fromKeys = (rules[0]["manipulators"] as! [JSONObject]).map { ($0["from"] as! JSONObject)["key_code"] as! String }
    check(fromKeys == ["left_shift", "left_option", "spacebar", "left_command", "left_arrow", "right_arrow"], "\(fromKeys)")
}

test("все 256 комбинаций групп проходят линтер Karabiner") {
    guard FileManager.default.fileExists(atPath: Karabiner.cliPath) else {
        print("  (karabiner_cli не найден — пропуск)")
        return
    }
    for mask in 1..<256 {
        let error = try Karabiner.lint(rules: RuleGenerator.rules(for: [kd83a], features: features(mask: mask)))
        check(error == nil, "маска \(mask): \(error ?? "")")
    }
}

// MARK: - karabiner.json

func sampleConfig(rules: [JSONObject]) -> JSONObject {
    [
        "global": ["show_in_menu_bar": true],
        "profiles": [
            ["name": "Other", "selected": false, "complex_modifications": ["rules": []]],
            [
                "name": "Default profile",
                "selected": true,
                "complex_modifications": ["rules": rules, "parameters": ["basic.simultaneous_threshold_milliseconds": 50]],
                "fn_function_keys": [["from": ["key_code": "f3"], "to": [["apple_vendor_keyboard_key_code": "mission_control"]]]],
            ],
        ],
    ]
}

func selectedRules(_ config: JSONObject) -> [String] {
    let profile = (config["profiles"] as! [JSONObject])[1]
    return ((profile["complex_modifications"] as! JSONObject)["rules"] as! [JSONObject]).map { $0["description"] as! String }
}

test("наши правила заменяются, чужие и остальной конфиг остаются") {
    let config = sampleConfig(rules: [
        ["description": "KD83A 0416:7472 — Windows Alt+Tab", "manipulators": []],
        ["description": "Моё правило", "manipulators": []],
        ["description": "CtrlAlt — старое", "manipulators": []],
    ])
    let merged = try KarabinerConfig.merged(config, rules: [["description": "CtrlAlt — новое", "manipulators": []]])
    check(selectedRules(merged) == ["CtrlAlt — новое", "Моё правило"], "\(selectedRules(merged))")
    let profile = (merged["profiles"] as! [JSONObject])[1]
    check(profile["fn_function_keys"] != nil, "пропали fn_function_keys")
    check((profile["complex_modifications"] as! JSONObject)["parameters"] != nil, "пропали parameters")
    check(merged["global"] != nil, "пропал global")
    check(selectedRules(try KarabinerConfig.merged(config, rules: [])) == ["Моё правило"])
}

test("клавиатура подхватывается из существующих правил") {
    let rules = RuleGenerator.rules(for: [kd83a], features: Features())
    check(KarabinerConfig.ownedKeyboards(in: sampleConfig(rules: rules)) == [kd83a])
    check(KarabinerConfig.ownedKeyboards(in: sampleConfig(rules: [])).isEmpty)
}

test("запись делает бэкап и пропускает неизменённый конфиг") {
    let dir = FileManager.default.temporaryDirectory.appending(path: "ctrlalt-check-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appending(path: "karabiner.json")
    let backups = dir.appending(path: "backups")
    try JSONSerialization.data(withJSONObject: sampleConfig(rules: [])).write(to: file)

    let rules = RuleGenerator.rules(for: [kd83a], features: Features())
    check(try KarabinerConfig.apply(rules: rules, to: file, backupDirectory: backups) != nil, "нет бэкапа")
    check(selectedRules(try KarabinerConfig.load(from: file)).count == 2)
    check(try KarabinerConfig.apply(rules: rules, to: file, backupDirectory: backups) == nil, "лишняя запись")
}

// MARK: - Устройства

test("список клавиатур: без встроенной, виртуальной и дублей") {
    let json = """
    [
      {"device_identifiers": {"is_keyboard": true, "is_pointing_device": true, "product_id": 29810, "vendor_id": 1046}, "transport": "USB"},
      {"device_identifiers": {"is_keyboard": true, "product_id": 29810, "vendor_id": 1046}, "transport": "USB"},
      {"device_identifiers": {"is_keyboard": true}, "is_built_in_keyboard": true, "product": "Apple Internal Keyboard / Trackpad"},
      {"device_identifiers": {"is_keyboard": true, "is_virtual_device": true, "product_id": 591, "vendor_id": 1452}, "product": "Karabiner DriverKit VirtualHIDKeyboard 1.8.0"},
      {"device_identifiers": {"is_keyboard": true, "product_id": 43138, "vendor_id": 13991}, "product": "WLMOUSE 1K RECEIVER", "manufacturer": "WL", "transport": "USB"},
      {"device_identifiers": {"is_pointing_device": true, "product_id": 43138, "vendor_id": 13991}, "product": "WLMOUSE 1K RECEIVER"}
    ]
    """
    let keyboards = try Karabiner.parseKeyboards(Data(json.utf8))
    check(keyboards.map(\.id) == [kd83a, KeyboardID(vendorID: 13991, productID: 43138)])
    check(keyboards.first?.title == "Клавиатура (0416:7472)")
    check(keyboards.first?.alsoPointing == false)
    check(keyboards.last?.title == "WLMOUSE 1K RECEIVER (36a7:a882)")
}

// MARK: - Установщик Karabiner

test("релиз Karabiner: берётся .dmg с github.com") {
    let json = """
    {"tag_name": "v16.3.0", "assets": [
      {"name": "Karabiner-Elements-16.3.0.dmg.sha256", "browser_download_url": "https://github.com/pqrs-org/Karabiner-Elements/releases/download/v16.3.0/x.sha256", "size": 64},
      {"name": "Karabiner-Elements-16.3.0.dmg", "browser_download_url": "https://github.com/pqrs-org/Karabiner-Elements/releases/download/v16.3.0/Karabiner-Elements-16.3.0.dmg", "size": 42388528}
    ]}
    """
    let release = try KarabinerInstaller.parseLatestRelease(Data(json.utf8))
    check(release.version == "16.3.0")
    check(release.diskImage.lastPathComponent == "Karabiner-Elements-16.3.0.dmg")
    check(release.size == 42388528)

    let foreign = json.replacingOccurrences(of: "https://github.com/pqrs-org/Karabiner-Elements/releases/download/v16.3.0/Karabiner", with: "https://example.com/Karabiner")
    check((try? KarabinerInstaller.parseLatestRelease(Data(foreign.utf8))) == nil, "ссылка не на github.com принята")
}

test("подпись установщика: только Developer ID Installer разработчика Karabiner") {
    let trusted = """
    Package "Karabiner-Elements.pkg":
       Status: signed by a developer certificate issued by Apple for distribution
       Notarization: trusted by the Apple notary service
       Certificate Chain:
        1. Developer ID Installer: Fumihiko Takayama (G43BCU2T37)
           Expires: 2027-02-01 00:00:00 +0000
        2. Developer ID Certification Authority
        3. Apple Root CA
    """
    check(KarabinerInstaller.isTrustedSignature(trusted))
    check(!KarabinerInstaller.isTrustedSignature(trusted.replacingOccurrences(of: "G43BCU2T37", with: "ABCDE12345")), "чужая команда принята")
    check(!KarabinerInstaller.isTrustedSignature(trusted.replacingOccurrences(of: "Developer ID Installer", with: "Developer ID Application")), "не installer-сертификат принят")
    check(!KarabinerInstaller.isTrustedSignature(trusted.replacingOccurrences(of: "Status: signed by a developer certificate issued by Apple for distribution", with: "Status: signed by untrusted certificate")), "недоверенная подпись принята")
    check(!KarabinerInstaller.isTrustedSignature("Package \"x.pkg\":\n   Status: no signature"), "неподписанный принят")
}

// MARK: - Плавная прокрутка (Mos)

test("прокрутка: значения по умолчанию как в Mos") {
    let s = MosScrollSettings()
    check(s.step == 33.6 && s.speed == 2.70 && s.duration == 4.35 && s.deadZone == 1.0)
    check(s.dash == MosKeyCode.optionL && s.toggle == MosKeyCode.shiftL && s.block == MosKeyCode.commandL)
    // Формула Mos: 1 - sqrt(duration / 5.2), три знака.
    check(s.durationTransition == 0.085, "\(s.durationTransition)")
    var fast = s
    fast.duration = 1
    check(fast.durationTransition == 0.561, "\(fast.durationTransition)")
}

test("прокрутка: старые настройки без новых полей читаются") {
    let partial = #"{"smooth":false,"step":50}"#
    let s = try JSONDecoder().decode(MosScrollSettings.self, from: Data(partial.utf8))
    check(s.smooth == false && s.step == 50)
    check(s.speed == 2.70 && s.dash == MosKeyCode.optionL)
    let noKey = #"{"dash":null}"#
    check(try JSONDecoder().decode(MosScrollSettings.self, from: Data(noKey.utf8)).dash == nil, "явное «нет» потерялось")
}

test("прокрутка: импорт настроек в формате Mos") {
    let suite = "ctrlalt.checks.mos-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    check(MosScrollSettings.importedFromMos(defaults) == nil, "пустые настройки приняты за Mos")

    defaults.set(1, forKey: "smooth")
    defaults.set(0, forKey: "reverse")
    defaults.set("40.5", forKey: "step")
    defaults.set("3.1", forKey: "speed")
    defaults.set("2.5", forKey: "duration")
    defaults.set(Data(#"{"code":56,"type":"keyboard"}"#.utf8), forKey: "dash")
    defaults.set(Data(#"{"code":3,"type":"mouse"}"#.utf8), forKey: "block")
    let s = MosScrollSettings.importedFromMos(defaults)
    check(s?.smooth == true && s?.reverse == false)
    check(s?.step == 40.5 && s?.speed == 3.1 && s?.duration == 2.5)
    check(s?.dash == MosKeyCode.shiftL, "dash \(String(describing: s?.dash))")
    check(s?.block == .some(nil), "кнопка мыши должна стать «нет»")
    check(s?.toggle == MosKeyCode.shiftL, "toggle по умолчанию")
}

print(failures == 0 ? "\nВсе проверки пройдены." : "\nОшибок: \(failures)")
exit(failures == 0 ? 0 : 1)
