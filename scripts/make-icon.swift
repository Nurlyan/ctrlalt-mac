// Рисует иконку приложения и собирает Resources/AppIcon.icns.
// Запуск: swift scripts/make-icon.swift (нужен только при изменении иконки).
import AppKit

let root = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Плитка в пропорциях иконок macOS: поле ~10% и скругление ~22%.
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.42, blue: 0.95, alpha: 1),
                        NSColor(srgbRed: 0.08, green: 0.22, blue: 0.62, alpha: 1)])!
        .draw(in: path, angle: -90)

    // Две «клавиши»: Ctrl и Alt.
    let keyW = tile.width * 0.36, keyH = tile.height * 0.36, gap = tile.width * 0.06
    let y = tile.midY - keyH / 2
    for (i, label) in ["Ctrl", "Alt"].enumerated() {
        let x = tile.midX - keyW - gap / 2 + CGFloat(i) * (keyW + gap)
        let key = NSRect(x: x, y: y, width: keyW, height: keyH)
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: key, xRadius: keyW * 0.16, yRadius: keyW * 0.16).fill()
        let font = NSFont.systemFont(ofSize: keyH * 0.32, weight: .semibold)
        let text = NSAttributedString(string: label, attributes: [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.08, green: 0.22, blue: 0.62, alpha: 1),
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: key.midX - size.width / 2, y: key.midY - size.height / 2))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}

let output = root.appending(path: "Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Готово: \(output.path)" : "iconutil завершился с ошибкой")
