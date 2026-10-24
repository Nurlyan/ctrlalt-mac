import AppKit
import CtrlAltCore
import SwiftUI

struct CtrlAltApp: App {
    // Не @State: в Command Line Tools нет плагина макросов SwiftUI. App создаётся один раз.
    private let model = AppModel()

    var body: some Scene {
        MenuBarExtra("CtrlAlt", systemImage: "keyboard") {
            MenuView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CtrlAlt").font(.headline)
                Text("Windows-сочетания").foregroundStyle(.secondary)
                Spacer()
                Toggle("Включено", isOn: $model.settings.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            karabinerStatus

            Divider()

            keyboardPicker

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Alt+Tab — переключение приложений", isOn: $model.settings.features.altTab)
                Toggle("Alt+Shift — смена языка", isOn: $model.settings.features.altShiftLayout)
                Toggle("Win+Space — смена языка", isOn: $model.settings.features.winSpaceLayout)
                Toggle("Win — Spotlight", isOn: $model.settings.features.winAloneSpotlight)
                Toggle("Win+Ctrl+←/→ — рабочие столы", isOn: $model.settings.features.winCtrlDesktops)
                Toggle("Ctrl+C/V/Z/Y… — как Command", isOn: $model.settings.features.ctrlShortcuts)
                Toggle("Ctrl+стрелки — по словам", isOn: $model.settings.features.ctrlWordNavigation)
                Toggle("Home/End — начало и конец строки", isOn: $model.settings.features.homeEnd)
                Toggle("Ctrl+колесо мыши — масштаб", isOn: $model.settings.scrollZoom)
            }
            .disabled(!model.settings.enabled)

            if model.scrollZoomNeedsPermission {
                statusRow("Для масштаба колесом нужен доступ «Универсальный доступ»", ok: false) {
                    Button("Разрешить") { model.requestScrollZoomPermission() }
                }
            }

            Text("Сочетания действуют только на выбранной клавиатуре. В терминалах Ctrl остаётся Ctrl, копирование — Ctrl+Shift+C/V.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = model.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(model.isError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle("Запускать при входе в систему", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            HStack {
                Button("Обновить") { model.refresh() }
                Button("Karabiner…") { NSWorkspace.shared.open(Karabiner.appURL) }
                    .disabled(!model.status.installed)
                Spacer()
                Button("Выйти") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { model.refresh() }
    }

    @ViewBuilder
    private var karabinerStatus: some View {
        let status = model.status
        if !status.installed {
            statusRow("Karabiner-Elements не установлен", ok: false) {
                Button("Скачать") { NSWorkspace.shared.open(Karabiner.downloadPage) }
            }
        } else if !status.driverActive {
            statusRow("Драйвер Karabiner не активирован", ok: false) {
                Button("Открыть Karabiner") { NSWorkspace.shared.open(Karabiner.appURL) }
            }
        } else if !status.configExists {
            statusRow("Откройте Karabiner один раз для начальной настройки", ok: false) {
                Button("Открыть") { NSWorkspace.shared.open(Karabiner.appURL) }
            }
        } else {
            statusRow("Karabiner \(status.version ?? "") · драйвер активен", ok: true) { EmptyView() }
        }
    }

    private func statusRow(_ text: String, ok: Bool, @ViewBuilder action: () -> some View) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(text).font(.callout)
            Spacer()
            action()
        }
    }

    @ViewBuilder
    private var keyboardPicker: some View {
        Picker("Клавиатура", selection: $model.settings.keyboard) {
            Text("Не выбрана").tag(KeyboardID?.none)
            ForEach(model.keyboardChoices, id: \.id) { choice in
                Text(choice.title).tag(KeyboardID?.some(choice.id))
            }
        }
        if model.selectedKeyboardAlsoPointing {
            Text("Похоже, это приёмник мыши, а не клавиатура. Проверьте выбор.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if model.settings.keyboard != nil {
            Text("Если сочетания не действуют, в Karabiner → Devices включите «Modify events» для этой клавиатуры.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
