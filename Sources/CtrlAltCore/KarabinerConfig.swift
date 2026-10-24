import Foundation

public enum KarabinerConfigError: LocalizedError {
    case missing(URL)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .missing(let url): "Нет файла \(url.path). Откройте Karabiner-Elements один раз, чтобы он его создал."
        case .invalid(let reason): "Не удалось разобрать karabiner.json: \(reason)"
        }
    }
}

/// Чтение и запись ~/.config/karabiner/karabiner.json.
///
/// Приложение владеет только своими правилами (по префиксу описания) и не трогает остальные.
public enum KarabinerConfig {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/karabiner/karabiner.json")
    }

    public static var backupDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/karabiner/ctrlalt_backups")
    }

    /// Правила, созданные этим приложением или вручную до него (KD83A).
    static let ownedPrefixes = [RuleGenerator.descriptionPrefix, "KD83A 0416:7472"]
    static let keptBackups = 20

    public static func isOwned(_ rule: JSONObject) -> Bool {
        guard let description = rule["description"] as? String else { return false }
        return ownedPrefixes.contains { description.hasPrefix($0) }
    }

    /// Возвращает конфиг, где в выбранном профиле наши правила заменены на `rules` (в начале списка).
    public static func merged(_ config: JSONObject, rules: [JSONObject]) throws -> JSONObject {
        guard var profiles = config["profiles"] as? [JSONObject], !profiles.isEmpty else {
            throw KarabinerConfigError.invalid("нет профилей")
        }
        let index = profiles.firstIndex { ($0["selected"] as? Bool) == true } ?? 0
        var profile = profiles[index]
        var complex = profile["complex_modifications"] as? JSONObject ?? [:]
        let existing = complex["rules"] as? [JSONObject] ?? []
        complex["rules"] = rules + existing.filter { !isOwned($0) }
        profile["complex_modifications"] = complex
        profiles[index] = profile

        var result = config
        result["profiles"] = profiles
        return result
    }

    /// Клавиатуры из device_if наших правил в выбранном профиле (для первого запуска).
    public static func ownedKeyboards(in config: JSONObject) -> [KeyboardID] {
        let profiles = config["profiles"] as? [JSONObject] ?? []
        guard let profile = profiles.first(where: { ($0["selected"] as? Bool) == true }) ?? profiles.first else { return [] }
        let rules = (profile["complex_modifications"] as? JSONObject)?["rules"] as? [JSONObject] ?? []
        var result: [KeyboardID] = []
        for rule in rules where isOwned(rule) {
            for manipulator in rule["manipulators"] as? [JSONObject] ?? [] {
                for condition in manipulator["conditions"] as? [JSONObject] ?? [] where condition["type"] as? String == "device_if" {
                    for identifier in condition["identifiers"] as? [JSONObject] ?? [] {
                        if let vendor = identifier["vendor_id"] as? Int, let product = identifier["product_id"] as? Int {
                            let id = KeyboardID(vendorID: vendor, productID: product)
                            if !result.contains(id) { result.append(id) }
                        }
                    }
                }
            }
        }
        return result
    }

    public static func load(from url: URL = defaultURL) throws -> JSONObject {
        guard FileManager.default.fileExists(atPath: url.path) else { throw KarabinerConfigError.missing(url) }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject else {
            throw KarabinerConfigError.invalid("корень не объект")
        }
        return object
    }

    /// Записывает правила. Возвращает путь бэкапа или nil, если конфиг не изменился.
    @discardableResult
    public static func apply(rules: [JSONObject], to url: URL = defaultURL, backupDirectory: URL = backupDirectory) throws -> URL? {
        let current = try load(from: url)
        let updated = try merged(current, rules: rules)
        if NSDictionary(dictionary: current).isEqual(to: updated) { return nil }

        let backup = try makeBackup(of: url, in: backupDirectory)
        let data = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .withoutEscapingSlashes])
        // Атомарная запись: Karabiner следит за файлом и не должен увидеть его наполовину записанным.
        try data.write(to: url, options: .atomic)
        return backup
    }

    static func makeBackup(of url: URL, in directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let backup = directory.appending(path: "karabiner-\(formatter.string(from: Date())).json")
        try fm.copyItem(at: url, to: backup)

        let old = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("karabiner-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(keptBackups)
        for file in old { try? fm.removeItem(at: file) }
        return backup
    }
}
