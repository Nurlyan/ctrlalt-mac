// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CtrlAlt",
    platforms: [.macOS(.v26)],
    targets: [
        // Чистая логика: генерация правил, конфиг Karabiner, список устройств.
        .target(name: "CtrlAltCore"),
        // Приложение в строке меню (и CLI-режим --print-rules).
        .executableTarget(name: "CtrlAlt", dependencies: ["CtrlAltCore"]),
        // Проверки логики: swift run CtrlAltChecks (XCTest и Swift Testing недоступны без Xcode).
        .executableTarget(
            name: "CtrlAltChecks",
            dependencies: ["CtrlAltCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
