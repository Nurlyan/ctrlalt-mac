import AppKit
import SwiftUI

struct CtrlAltApp: App {
    // Не @State: в Command Line Tools нет плагина макросов SwiftUI. App создаётся один раз.
    private let model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            QuickPanel(model: model)
        } label: {
            Image(systemName: model.settings.enabled ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)

        Window("CtrlAlt", id: "settings") {
            SettingsView(model: model)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 780, height: 580)
    }
}
