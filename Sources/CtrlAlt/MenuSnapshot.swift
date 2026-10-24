import AppKit
import SwiftUI

/// Рисует меню в PNG с реальным состоянием (Karabiner, клавиатуры), ничего не записывая в конфиг.
@MainActor
enum MenuSnapshot {
    static func write(to url: URL) {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: MenuView(model: AppModel(applyOnLaunch: false)).background(Color(nsColor: .windowBackgroundColor)))
        view.frame.size = view.fittingSize
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
