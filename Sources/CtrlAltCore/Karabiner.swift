import Foundation

/// Состояние установленного Karabiner-Elements.
public struct KarabinerStatus: Equatable, Sendable {
    public var installed: Bool
    public var version: String?
    public var driverActive: Bool
    public var configExists: Bool

    public var ready: Bool { installed && driverActive && configExists }

    public init(installed: Bool, version: String?, driverActive: Bool, configExists: Bool) {
        self.installed = installed
        self.version = version
        self.driverActive = driverActive
        self.configExists = configExists
    }
}

/// Клавиатура, которую видит Karabiner (одна запись на VID/PID).
public struct KeyboardInfo: Identifiable, Hashable, Sendable {
    public var id: KeyboardID
    public var name: String?
    public var transport: String?
    /// Устройство ещё и указатель: например, приёмник мыши, который притворяется клавиатурой.
    public var alsoPointing: Bool

    public var title: String {
        let base = name ?? "Клавиатура"
        return "\(base) (\(id.hex))"
    }
}

public enum Karabiner {
    public static let appURL = URL(filePath: "/Applications/Karabiner-Elements.app")
    public static let eventViewerURL = URL(filePath: "/Applications/Karabiner-EventViewer.app")
    public static let cliPath = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
    public static let downloadPage = URL(string: "https://karabiner-elements.pqrs.org/")!
    static let driverBundleID = "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice"

    public static func status() -> KarabinerStatus {
        let fm = FileManager.default
        let installed = fm.fileExists(atPath: cliPath) && fm.fileExists(atPath: appURL.path)
        let version = Bundle(url: appURL)?.infoDictionary?["CFBundleShortVersionString"] as? String
        let extensions = (try? run("/usr/bin/systemextensionsctl", ["list"]).output) ?? ""
        let driverActive = extensions.split(separator: "\n").contains {
            $0.contains(driverBundleID) && $0.contains("[activated enabled]")
        }
        return KarabinerStatus(
            installed: installed,
            version: version,
            driverActive: driverActive,
            configExists: fm.fileExists(atPath: KarabinerConfig.defaultURL.path)
        )
    }

    /// Внешние клавиатуры: без встроенной и виртуальных, по одной записи на VID/PID.
    public static func connectedKeyboards() throws -> [KeyboardInfo] {
        let result = try run(cliPath, ["--list-connected-devices"])
        return try parseKeyboards(Data(result.output.utf8))
    }

    public static func parseKeyboards(_ data: Data) throws -> [KeyboardInfo] {
        guard let devices = try JSONSerialization.jsonObject(with: data) as? [JSONObject] else { return [] }
        var byID: [KeyboardID: KeyboardInfo] = [:]
        var order: [KeyboardID] = []
        for device in devices {
            let ids = device["device_identifiers"] as? JSONObject ?? [:]
            guard (ids["is_keyboard"] as? Bool) == true,
                  (ids["is_virtual_device"] as? Bool) != true,
                  (device["is_built_in_keyboard"] as? Bool) != true,
                  let vendor = ids["vendor_id"] as? Int,
                  let product = ids["product_id"] as? Int
            else { continue }

            let id = KeyboardID(vendorID: vendor, productID: product)
            var info = byID[id] ?? KeyboardInfo(id: id, name: nil, transport: nil, alsoPointing: false)
            if byID[id] == nil { order.append(id) }
            info.name = info.name ?? (device["product"] as? String) ?? (device["manufacturer"] as? String)
            info.transport = info.transport ?? (device["transport"] as? String)
            // Составное устройство: интерфейс «только клавиатура» перевешивает интерфейс клавиатура+мышь.
            let pointing = (ids["is_pointing_device"] as? Bool) == true
            info.alsoPointing = byID[id] == nil ? pointing : (info.alsoPointing && pointing)
            byID[id] = info
        }
        return order.compactMap { byID[$0] }
    }

    /// Проверка правил встроенным линтером Karabiner. Возвращает текст ошибки или nil.
    public static func lint(rules: [JSONObject]) throws -> String? {
        let file = FileManager.default.temporaryDirectory.appending(path: "ctrlalt-lint-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = try JSONSerialization.data(withJSONObject: ["title": "CtrlAlt", "rules": rules])
        try data.write(to: file)
        let result = try run(cliPath, ["--lint-complex-modifications", file.path])
        return result.status == 0 ? nil : result.output
    }

    struct RunResult {
        var status: Int32
        var output: String
    }

    static func run(_ path: String, _ arguments: [String]) throws -> RunResult {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return RunResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
