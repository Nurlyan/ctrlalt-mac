import AppKit
import CtrlAltCore
import Foundation
import Observation
import ServiceManagement

/// Ход установки Karabiner-Elements из приложения.
enum InstallState: Equatable {
    case idle
    case working(String, progress: Double?)
    /// Установщик macOS открыт; дальше пользователь проходит его и шаги настройки.
    case installerOpened
    case failed(String)

    var isWorking: Bool { if case .working = self { true } else { false } }
}

struct AppSettings: Codable, Equatable, Sendable {
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
            if karabinerPart != oldKarabinerPart { apply() }  // несколько быстрых изменений — одна запись
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
    /// Открытый раздел окна настроек (здесь, а не в @State: макросов SwiftUI нет в Command Line Tools).
    var section: SettingsSection = .general
    var install: InstallState = .idle
    /// Идёт запись правил в Karabiner (в фоне).
    var isApplying = false

    var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }

    var selectedKeyboardInfo: KeyboardInfo? { keyboards.first { $0.id == settings.keyboard } }

    var keyboardSubtitle: String {
        guard let id = settings.keyboard else { return "Клавиатура не выбрана" }
        guard let info = selectedKeyboardInfo else { return "Клавиатура \(id.hex) не подключена" }
        return [info.name ?? "Клавиатура \(id.hex)", info.transport].compactMap { $0 }.joined(separator: " · ")
    }

    /// Смена языка: Alt+Shift и Win+Space включаются и выключаются вместе в быстрой панели.
    var languageSwitching: Bool {
        get { settings.features.altShiftLayout || settings.features.winSpaceLayout }
        set {
            settings.features.altShiftLayout = newValue
            settings.features.winSpaceLayout = newValue
        }
    }

    /// live == false: режим показа интерфейса, без записи конфига и без перехвата колеса.
    init(live: Bool = true) {
        self.live = live
        let saved = UserDefaults.standard.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
        if let saved {
            settings = saved
        } else {
            // Первый запуск: подхватываем клавиатуру из уже записанных правил (например, KD83A).
            var initial = AppSettings()
            if let config = try? KarabinerConfig.load() {
                initial.keyboard = KarabinerConfig.ownedKeyboards(in: config).first
            }
            settings = initial
        }
        // Статус нужен сразу (от него зависит, открывать ли окно при запуске) и занимает ~10 мс;
        // список клавиатур подгружается в фоне.
        status = Karabiner.status()
        refresh()
        // Karabiner не готов: окно настроек откроется на разделе с шагами установки.
        if !status.ready { section = .karabiner }
        // Настройки уже сохранены через приложение: обновляем правила (например, после обновления CtrlAlt).
        // Без изменений запись пропускается.
        if saved != nil { apply(after: .zero) }
    }

    private var hasSavedSettings: Bool { UserDefaults.standard.data(forKey: Self.settingsKey) != nil }

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

    /// Обновляет статус Karabiner и список клавиатур. Внешние команды (~80 мс) идут в фоне,
    /// чтобы панель открывалась без задержки; повторные вызовы во время обновления пропускаются.
    func refresh() {
        guard refreshTask == nil else { return }
        let preview = previewStatus
        refreshTask = Task { [weak self] in
            let (status, keyboards) = await Task.detached(priority: .userInitiated) {
                (preview ?? Karabiner.status(), (try? Karabiner.connectedKeyboards()) ?? [])
            }.value
            guard let self else { return }
            self.refreshTask = nil
            if status != self.status { self.status = status }
            if keyboards != self.keyboards { self.keyboards = keyboards }
            self.updateScrollZoom()
            if !status.ready { self.watchKarabinerSetup() }
        }
    }

    /// Пока Karabiner не готов, раз в 2 секунды проверяем его состояние: шаги установки
    /// отмечаются сами, а когда всё готово, правила записываются без лишних нажатий.
    private func watchKarabinerSetup() {
        guard live, setupPoll == nil else { return }
        setupPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                let current = await Task.detached { Karabiner.status() }.value
                if current != self.status { self.status = current }
                if current.ready {
                    self.setupPoll = nil
                    self.install = .idle
                    self.refresh()
                    if self.hasSavedSettings || self.settings.keyboard != nil { self.apply() }
                    return
                }
            }
        }
    }

    /// Скачивает официальный Karabiner-Elements, проверяет подпись и открывает установщик macOS.
    func installKarabiner() {
        guard !install.isWorking else { return }
        install = .working("Ищем последнюю версию…", progress: nil)
        Task {
            do {
                let release = try await KarabinerInstaller.fetchLatestRelease()
                let size = ByteCountFormatter.string(fromByteCount: Int64(release.size), countStyle: .file)
                install = .working("Скачиваем Karabiner-Elements \(release.version) (\(size))…", progress: 0)
                let image = try await KarabinerInstaller.download(release) { fraction in
                    Task { @MainActor in
                        guard case .working(let text, _) = self.install else { return }
                        self.install = .working(text, progress: fraction)
                    }
                }
                install = .working("Проверяем подпись установщика…", progress: nil)
                let package = try await Task.detached { try KarabinerInstaller.extractVerifiedPackage(from: image) }.value
                NSWorkspace.shared.open(package)
                install = .installerOpened
                watchKarabinerSetup()
            } catch {
                install = .failed(error.localizedDescription)
            }
        }
    }

    func updateScrollZoom() {
        guard live else {
            scrollZoomNeedsPermission = settings.scrollZoom && !ScrollZoom.hasPermission
            return
        }
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

    @ObservationIgnored private let live: Bool
    /// Только для --show-ui: подставное состояние Karabiner, которое не перезаписывается при обновлении.
    @ObservationIgnored var previewStatus: KarabinerStatus? {
        didSet { if let previewStatus { status = previewStatus } }
    }
    @ObservationIgnored private var permissionPoll: Task<Void, Never>?
    @ObservationIgnored private var setupPoll: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var applyTask: Task<Void, Never>?

    func requestScrollZoomPermission() {
        ScrollZoom.requestPermission()
    }

    /// Кнопка «Применить»: сохраняет текущие настройки и записывает правила сразу.
    func applyNow() {
        save()
        apply(after: .zero)
    }

    /// Записывает правила в karabiner.json. Вызывается при изменении настроек, по кнопке
    /// и при запуске, только если настройки уже сохранены через приложение.
    ///
    /// Изменения за `delay` объединяются в одну запись (например, плитка «Смена языка» меняет две
    /// настройки сразу), а проверка линтером и запись (~60 мс) идут в фоне, не задерживая анимации.
    func apply(after delay: Duration = .milliseconds(250)) {
        guard live else { return }
        applyTask?.cancel()
        let settings = self.settings
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.isApplying = true
            let outcome = await Task.detached(priority: .userInitiated) { Self.writeRules(settings) }.value
            self.isApplying = false
            if outcome.status != self.status { self.status = outcome.status }
            self.report(outcome.message, error: outcome.isError)
        }
    }

    private struct ApplyOutcome: Sendable {
        var status: KarabinerStatus
        var message: String
        var isError: Bool
    }

    private nonisolated static func writeRules(_ settings: AppSettings) -> ApplyOutcome {
        let status = Karabiner.status()
        guard status.installed else { return ApplyOutcome(status: status, message: "Karabiner-Elements не установлен", isError: true) }
        guard status.configExists else {
            return ApplyOutcome(status: status, message: "Откройте Karabiner-Elements один раз, чтобы он создал настройки", isError: true)
        }

        let rules: [JSONObject]
        if settings.enabled {
            guard let keyboard = settings.keyboard else {
                return ApplyOutcome(status: status, message: "Выберите внешнюю клавиатуру", isError: false)
            }
            rules = RuleGenerator.rules(for: [keyboard], features: settings.features)
        } else {
            rules = []
        }

        do {
            if !rules.isEmpty, let lintError = try Karabiner.lint(rules: rules) {
                return ApplyOutcome(status: status, message: "Karabiner отклонил правила: \(lintError)", isError: true)
            }
            try KarabinerConfig.apply(rules: rules)
            let time = Date().formatted(date: .omitted, time: .shortened)
            let text = rules.isEmpty ? "Правила CtrlAlt выключены (\(time))" : "Правила применены (\(time))"
            return ApplyOutcome(status: status, message: text, isError: false)
        } catch {
            return ApplyOutcome(status: status, message: error.localizedDescription, isError: true)
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
        guard live else { return }
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    private func report(_ text: String, error: Bool) {
        message = text
        isError = error
    }
}
