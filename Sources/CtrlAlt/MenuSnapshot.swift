import AppKit
import CtrlAltCore
import SwiftUI

/// Отладочный показ интерфейса без клика по строке меню: настоящие окна, чтобы стекло рисовалось как в жизни.
/// Печатает номера окон для `screencapture -l` и закрывается через `seconds`. Конфиг Karabiner не меняет.
@MainActor
enum MenuSnapshot {
    static func show(section: SettingsSection, seconds: Double) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let model = AppModel(live: false)
        model.section = section
        // CTRLALT_PREVIEW_KARABINER: показать шаги установки, будто Karabiner ещё не готов.
        switch ProcessInfo.processInfo.environment["CTRLALT_PREVIEW_KARABINER"] {
        case "missing":
            model.previewStatus = KarabinerStatus(installed: false, version: nil, driverActive: false, configExists: false)
        case "downloading":
            model.previewStatus = KarabinerStatus(installed: false, version: nil, driverActive: false, configExists: false)
            model.install = .working("Скачиваем Karabiner-Elements 16.3.0 (42,4 МБ)…", progress: 0.42)
        case "driver":
            model.previewStatus = KarabinerStatus(installed: true, version: "16.3.0", driverActive: false, configExists: false)
        default:
            break
        }

        let panel = window(QuickPanel(model: model), title: "Панель", size: nil, origin: NSPoint(x: 80, y: 200))
        let settings = window(SettingsView(model: model), title: "CtrlAlt", size: NSSize(width: 780, height: 580), origin: NSPoint(x: 440, y: 120))
        // Активное окно, иначе на снимке неактивная палитра: серые переключатели и приглушённое стекло.
        NSRunningApplication.current.activate(options: .activateAllWindows)
        app.activate()
        settings.makeKeyAndOrderFront(nil)
        print("panel \(panel.windowNumber)")
        print("settings \(settings.windowNumber)")
        fflush(stdout)

        // CTRLALT_SNAPSHOT_DIR: сохранить окна в PNG (стекло и материалы в таком снимке упрощены).
        if let dir = ProcessInfo.processInfo.environment["CTRLALT_SNAPSHOT_DIR"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                save(panel, to: URL(filePath: dir).appending(path: "panel.png"))
                save(settings, to: URL(filePath: dir).appending(path: "settings-\(section.rawValue).png"))
            }
        }
        // CTRLALT_SNAPSHOT_ANIMATE: выключить в 2.0 с и снять панель в нескольких кадрах перехода.
        if let dir = ProcessInfo.processInfo.environment["CTRLALT_SNAPSHOT_DIR"],
           ProcessInfo.processInfo.environment["CTRLALT_SNAPSHOT_ANIMATE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(Motion.power) { model.settings.enabled.toggle() }
            }
            for ms in [60, 150, 260, 600] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 + Double(ms) / 1000) {
                    save(panel, to: URL(filePath: dir).appending(path: "panel-\(ms)ms.png"))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
        app.run()
    }

    private typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// Снимок собственного окна через CGWindowListCreateImage (в Swift SDK помечена недоступной,
    /// поэтому через dlsym). Свои окна приложение снимает без разрешения на запись экрана.
    private static func save(_ window: NSWindow, to url: URL) {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else {
            print("CGWindowListCreateImage недоступна")
            return
        }
        let capture = unsafeBitCast(symbol, to: WindowImageFunction.self)
        // kCGWindowListOptionIncludingWindow = 1 << 3; kCGWindowImageBoundsIgnoreFraming | BestResolution.
        guard let image = capture(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue() else {
            print("не удалось снять окно \(window.windowNumber)")
            return
        }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func window(_ view: some View, title: String, size: NSSize?, origin: NSPoint) -> NSWindow {
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        if let size {
            window.setContentSize(size)
            window.styleMask.insert(.fullSizeContentView)
            window.toolbarStyle = .unified
        }
        window.setFrameOrigin(origin)
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
