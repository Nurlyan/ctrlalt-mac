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

//   CtrlAlt --snapshot out.png         — нарисовать меню в PNG (проверка вёрстки без клика по строке меню).
if arguments.count > 2, arguments[1] == "--snapshot" {
    MenuSnapshot.write(to: URL(filePath: arguments[2]))
    exit(0)
}

CtrlAltApp.main()
