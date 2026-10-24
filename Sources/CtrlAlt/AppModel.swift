import CtrlAltCore
import Foundation
import Observation
import ServiceManagement

struct AppSettings: Codable, Equatable {
    var enabled = true
    var keyboard: KeyboardID?
    var features = Features()
    /// Ctrl + колесо мыши — масштаб (работает в приложении, не в Karabiner).
    var scrollZoom = true

    init() {}

    // Новые поля, которых нет в сохранённых настройках, получают значение по умолчанию.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        keyboard = try c.decodeIfPresent(KeyboardID.self, forKey: .keyboard)
        features = try c.decodeIfPresent(Features.self, forKey: .features) ?? Features()
        scrollZoom = try c.decodeIfPresent(Bool.self, forKey: .scrollZoom) ?? true
    }
}

@MainActor
@Observable
final class AppModel {
    private static let settingsKey = "settings"

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            updateScrollZoom()
            // Масштаб колесом живёт в приложении: правила Karabiner от него не зависят.
            var karabinerPart = settings, oldKarabinerPart = oldValue
            karabinerPart.scrollZoom = false
            oldKarabinerPart.scrollZoom = false
            if karabinerPart != oldKarabinerPart { apply() }
        }
    }
    private let scrollZoom = ScrollZoom()
    /// Масштаб колесом включён в настройках, но нет разрешения «Универсальный доступ».
    var scrollZoomNeedsPermission = false
    var status = KarabinerStatus(installed: false, version: nil, driverActive: false, configExists: false)
    var keyboards: [KeyboardInfo] = []
    var message: String?
    var isError = false
    var launchAtLogin = SMAppService.mainApp.status == .enabled

    init(applyOnLaunch: Bool = true) {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
            // Настройки уже сохранены через приложение: обновляем правила (например, после обновления CtrlAlt).
            // Без изменений apply ничего не записывает.
            refresh()
            if applyOnLaunch { apply() }
            return
        } else {
            // Первый запуск: подхватываем клавиатуру из уже записанных правил (например, KD83A).
            var initial = AppSettings()
            if let config = try? KarabinerConfig.load() {
                initial.keyboard = KarabinerConfig.ownedKeyboards(in: config).first
            }
            settings = initial
        }
        refresh()
    }

    /// Список для выбора: подключённые клавиатуры плюс сохранённая, если она сейчас отключена.
    var keyboardChoices: [(id: KeyboardID, title: String)] {
        var choices = keyboards.map { (id: $0.id, title: $0.title) }
        if let saved = settings.keyboard, !keyboards.contains(where: { $0.id == saved }) {
            choices.append((id: saved, title: "Клавиатура (\(saved.hex)) — не подключена"))
        }
        return choices
    }

    var selectedKeyboardAlsoPointing: Bool {
        keyboards.first { $0.id == settings.keyboard }?.alsoPointing ?? false
    }

    func refresh() {
        status = Karabiner.status()
        keyboards = (try? Karabiner.connectedKeyboards()) ?? []
        updateScrollZoom()
    }

    func updateScrollZoom() {
        guard settings.enabled, settings.scrollZoom else {
            scrollZoom.stop()
            scrollZoomNeedsPermission = false
            return
        }
        scrollZoomNeedsPermission = !scrollZoom.start()
        // Ждём, пока пользователь выдаст разрешение в Системных настройках.
        if scrollZoomNeedsPermission, permissionPoll == nil {
            permissionPoll = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard let self else { return }
                    if ScrollZoom.hasPermission {
                        self.permissionPoll = nil
                        self.updateScrollZoom()
                        return
                    }
                }
            }
        }
    }

    @ObservationIgnored private var permissionPoll: Task<Void, Never>?

    func requestScrollZoomPermission() {
        ScrollZoom.requestPermission()
    }

    /// Кнопка «Применить»: сохраняет текущие настройки и записывает правила.
    func applyNow() {
        save()
        apply()
    }

    /// Записывает правила в karabiner.json. Вызывается при изменении настроек, по кнопке
    /// и при запуске, только если настройки уже сохранены через приложение.
    func apply() {
        refresh()
        guard status.installed else { return report("Karabiner-Elements не установлен", error: true) }
        guard status.configExists else { return report("Откройте Karabiner-Elements один раз, чтобы он создал настройки", error: true) }

        let rules: [JSONObject]
        if settings.enabled {
            guard let keyboard = settings.keyboard else { return report("Выберите внешнюю клавиатуру", error: false) }
            rules = RuleGenerator.rules(for: [keyboard], features: settings.features)
        } else {
            rules = []
        }

        do {
            if !rules.isEmpty, let lintError = try Karabiner.lint(rules: rules) {
                return report("Karabiner отклонил правила: \(lintError)", error: true)
            }
            try KarabinerConfig.apply(rules: rules)
            let time = Date().formatted(date: .omitted, time: .shortened)
            report(rules.isEmpty ? "Правила CtrlAlt выключены (\(time))" : "Правила применены (\(time))", error: false)
        } catch {
            report(error.localizedDescription, error: true)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            report("Автозапуск: \(error.localizedDescription)", error: true)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    private func report(_ text: String, error: Bool) {
        message = text
        isError = error
    }
}
