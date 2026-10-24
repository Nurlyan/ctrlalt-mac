import AppKit
import CtrlAltCore
import SwiftUI

/// Шаги подготовки Karabiner-Elements: установка, драйвер и разрешения, первый запуск.
/// Состояние шагов обновляется само (AppModel опрашивает Karabiner, пока он не готов).
struct KarabinerSetupSteps: View {
    @Bindable var model: AppModel

    private var status: KarabinerStatus { model.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SetupStep(
                number: 1,
                title: "Установить Karabiner-Elements",
                detail: "CtrlAlt скачает официальный установщик с GitHub pqrs.org и проверит подпись разработчика. macOS попросит пароль администратора.",
                done: status.installed,
                current: !status.installed
            ) {
                installControls
            }
            SetupStep(
                number: 2,
                title: "Разрешить драйвер и мониторинг ввода",
                detail: "Karabiner сам покажет запросы. Включите его в «Основные → Объекты входа и расширения» и в «Конфиденциальность → Мониторинг ввода».",
                done: status.driverActive,
                current: status.installed && !status.driverActive
            ) {
                HStack {
                    Button("Открыть Karabiner", systemImage: "gearshape.2") {
                        NSWorkspace.shared.open(Karabiner.appURL)
                    }
                    .buttonStyle(.glassProminent)
                    Button("Системные настройки", systemImage: "gear") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.glass)
                }
            }
            SetupStep(
                number: 3,
                title: "Запустить Karabiner один раз",
                detail: "Он создаст файл настроек, в который CtrlAlt запишет правила.",
                done: status.configExists,
                current: status.installed && status.driverActive && !status.configExists
            ) {
                Button("Открыть Karabiner", systemImage: "gearshape.2") {
                    NSWorkspace.shared.open(Karabiner.appURL)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(.vertical, 6)
        .animation(.spring(duration: 0.35), value: status)
    }

    @ViewBuilder
    private var installControls: some View {
        switch model.install {
        case .idle:
            HStack {
                Button("Установить", systemImage: "arrow.down.circle.fill") { model.installKarabiner() }
                    .buttonStyle(.glassProminent)
                Button("Скачать вручную") { NSWorkspace.shared.open(Karabiner.downloadPage) }
                    .buttonStyle(.link)
            }
        case .working(let text, let progress):
            VStack(alignment: .leading, spacing: 6) {
                if let progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360, alignment: .leading)
        case .installerOpened:
            Label("Установщик открыт — пройдите его шаги", systemImage: "shippingbox.fill")
                .foregroundStyle(.secondary)
        case .failed(let error):
            VStack(alignment: .leading, spacing: 6) {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Повторить", systemImage: "arrow.clockwise") { model.installKarabiner() }
                        .buttonStyle(.glassProminent)
                    Button("Скачать вручную") { NSWorkspace.shared.open(Karabiner.downloadPage) }
                        .buttonStyle(.link)
                }
            }
        }
    }
}

/// Один шаг: кружок с номером или галочкой, текст и действия (только у текущего шага).
struct SetupStep<Actions: View>: View {
    var number: Int
    var title: String
    var detail: String
    var done: Bool
    var current: Bool
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(current ? Color.white : Color.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .background(done ? Color.green : current ? Color.blue : Color.secondary.opacity(0.15), in: .circle)
            .glassEffect(.regular, in: .circle)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(done || current ? .primary : .secondary)
                if !done {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if current {
                    actions.padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Карточка в панели строки меню, пока Karabiner не готов.
struct KarabinerSetupCard: View {
    @Bindable var model: AppModel
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: model.status.installed ? "wrench.and.screwdriver.fill" : "shippingbox.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.orange)
            Text(model.status.installed ? "Завершите настройку Karabiner" : "Нужен Karabiner-Elements")
                .font(.headline)
            Text(model.status.installed
                 ? "Осталось разрешить драйвер и запустить Karabiner один раз."
                 : "Он обрабатывает нажатия клавиш. CtrlAlt установит его за пару кликов.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if case .working(let text, let progress) = model.install {
                VStack(spacing: 4) {
                    if let progress { ProgressView(value: progress) } else { ProgressView().controlSize(.small) }
                    Text(text).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button(model.status.installed ? "Продолжить" : "Установить", systemImage: model.status.installed ? "arrow.right.circle.fill" : "arrow.down.circle.fill") {
                    if !model.status.installed { model.installKarabiner() }
                    openSettings()
                }
                .buttonStyle(.glassProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
