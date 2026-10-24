// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CtrlAlt",
    platforms: [.macOS(.v26)],
    targets: [
        // Чистая логика: генерация правил, конфиг Karabiner, список устройств.
        .target(name: "CtrlAltCore"),
        // Плавная прокрутка из Mos (https://github.com/Caldis/Mos, CC BY-NC 4.0), см. Sources/MosScroll/NOTICE.md.
        // Код Mos написан под Swift 5, поэтому модуль собирается в режиме Swift 5.
        .target(
            name: "MosScroll",
            exclude: ["NOTICE.md"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Приложение в строке меню (и CLI-режим --print-rules).
        .executableTarget(name: "CtrlAlt", dependencies: ["CtrlAltCore", "MosScroll"]),
        // Проверки логики: swift run CtrlAltChecks (XCTest и Swift Testing недоступны без Xcode).
        .executableTarget(
            name: "CtrlAltChecks",
            dependencies: ["CtrlAltCore", "MosScroll"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
