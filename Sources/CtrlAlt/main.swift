import CtrlAltCore
import Foundation

// CLI-режим для проверки без интерфейса:
//   CtrlAlt --print-rules [VID:PID]   — правила со всеми группами в формате complex modifications.
let arguments = CommandLine.arguments
if arguments.count > 1, arguments[1] == "--print-rules" {
    var keyboard = KeyboardID(vendorID: 0x0416, productID: 0x7472)
    if arguments.count > 2 {
        let parts = arguments[2].split(separator: ":").compactMap { Int($0, radix: 16) }
        guard parts.count == 2 else {
            FileHandle.standardError.write(Data("Ожидается VID:PID в hex, например 0416:7472\n".utf8))
            exit(2)
        }
        keyboard = KeyboardID(vendorID: parts[0], productID: parts[1])
    }
    let rules = RuleGenerator.rules(for: [keyboard], features: Features())
    let data = try JSONSerialization.data(
        withJSONObject: ["title": "CtrlAlt", "rules": rules],
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

//   CtrlAlt --check-karabiner-download     — скачать последний Karabiner и проверить подпись, не устанавливая.
if arguments.count > 1, arguments[1] == "--check-karabiner-download" {
    do {
        let release = try await KarabinerInstaller.fetchLatestRelease()
        print("Релиз \(release.version): \(release.diskImage.absoluteString) (\(release.size) байт)")
        let image = try await KarabinerInstaller.download(release) { _ in }
        print("Скачано: \(image.path)")
        let package = try KarabinerInstaller.extractVerifiedPackage(from: image)
        print("Подпись проверена: \(package.path)")
        exit(0)
    } catch {
        print("Ошибка: \(error.localizedDescription)")
        exit(1)
    }
}

//   CtrlAlt --show-ui [раздел] [секунды]  — открыть панель и окно настроек для проверки вёрстки.
if arguments.count > 1, arguments[1] == "--show-ui" {
    let section = arguments.count > 2 ? SettingsSection(rawValue: arguments[2]) ?? .general : .general
    let seconds = arguments.count > 3 ? Double(arguments[3]) ?? 15 : 15
    MenuSnapshot.show(section: section, seconds: seconds)
}

CtrlAltApp.main()
