import AppKit
import CtrlAltCore
import MosScroll
import SwiftUI

/// Окно настроек в духе «Системных настроек»: боковая панель и сгруппированные разделы.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.section) {
                profileCard
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
                Section {
                    ForEach(SettingsSection.allCases) { section in
                        NavigationLink(value: section) {
                            Label {
                                Text(section.title)
                            } icon: {
                                IconBadge(symbol: section.symbol, color: section.color)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            // Разделы сменяются плавно: старый растворяется, новый проявляется с небольшим сдвигом.
            ZStack {
                detail
                    .id(model.section)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .animation(Motion.smooth, value: model.section)
            .navigationTitle(model.section.title)
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear { model.refresh() }
    }

    private var profileCard: some View {
        HStack(spacing: 10) {
            AppIconImage(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("CtrlAlt").font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.settings.enabled ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(model.settings.enabled ? "Включено" : "Выключено")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.interpolate)
                }
            }
        }
        .padding(.vertical, 6)
        .animation(Motion.power, value: model.settings.enabled)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .general: GeneralPage(model: model)
        case .keyboard: KeyboardPage(model: model)
        case .shortcuts: ShortcutsPage(model: model)
        case .mouse: MousePage(model: model)
        case .karabiner: KarabinerPage(model: model)
        case .about: AboutPage(model: model)
        }
    }
}

// MARK: - Основные

struct GeneralPage: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Button {
                        withAnimation(Motion.power) { model.settings.enabled.toggle() }
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(model.settings.enabled ? Color.white : Color.secondary)
                            .symbolEffect(.bounce.down, value: model.settings.enabled)
                            .frame(width: 64, height: 64)
                            .contentShape(.circle)
                            .glassEffect(
                                model.settings.enabled ? .regular.tint(.blue).interactive() : .regular.interactive(),
                                in: .circle
                            )
                            .background(
                                Circle()
                                    .fill(LinearGradient(colors: [.cyan, .blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .blur(radius: 6)
                                    .opacity(model.settings.enabled ? 0.85 : 0)
                                    .scaleEffect(model.settings.enabled ? 1 : 0.7)
                            )
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.settings.enabled ? "Windows-сочетания включены" : "Windows-сочетания выключены")
                            .font(.title3.weight(.semibold))
                            .contentTransition(.interpolate)
                        Text(model.keyboardSubtitle)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .animation(Motion.power, value: model.settings.enabled)
            }

            Section("Состояние") {
                StatusLine(
                    text: model.status.ready ? "Karabiner \(model.status.version ?? "") готов" : "Karabiner требует внимания",
                    ok: model.status.ready
                ) {
                    if !model.status.ready {
                        Button("Подробнее") { withAnimation(Motion.smooth) { model.section = .karabiner } }
                    }
                }
                StatusLine(
                    text: model.keyboardSubtitle,
                    ok: model.settings.keyboard != nil
                ) {
                    Button("Выбрать") { withAnimation(Motion.smooth) { model.section = .keyboard } }
                }
                if let message = model.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(model.isError ? .red : .secondary)
                        .contentTransition(.opacity)
                        .animation(Motion.smooth, value: message)
                }
            }

            Section {
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            } footer: {
                HStack {
                    Spacer()
                    Button("Применить правила") { model.applyNow() }
                        .buttonStyle(.glassProminent)
                        .disabled(model.settings.keyboard == nil && model.settings.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Клавиатура

struct KeyboardPage: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                if model.keyboardChoices.isEmpty {
                    Text("Внешние клавиатуры не найдены. Подключите клавиатуру и нажмите «Обновить».")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.keyboardChoices, id: \.id) { choice in
                    keyboardRow(choice.id, title: choice.title)
                }
            } header: {
                Text("Внешние клавиатуры")
            } footer: {
                HStack {
                    Text("Сочетания действуют только на выбранной клавиатуре. Встроенная клавиатура MacBook не меняется.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Обновить", systemImage: "arrow.clockwise") { model.refresh() }
                        .buttonStyle(.glass)
                }
            }

            Section("Если сочетания не действуют") {
                Label {
                    Text("Откройте Karabiner → Devices и включите «Modify events» для этой клавиатуры.")
                } icon: {
                    IconBadge(symbol: "lightbulb.fill", color: .yellow)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func keyboardRow(_ id: KeyboardID, title: String) -> some View {
        let info = model.keyboards.first { $0.id == id }
        let selected = model.settings.keyboard == id
        return Button {
            withAnimation(Motion.snappy) { model.settings.keyboard = selected ? nil : id }
        } label: {
            HStack(spacing: 12) {
                IconBadge(symbol: "keyboard", color: info == nil ? .gray : .blue, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info?.name ?? "Клавиатура")
                    Text([id.hex, info?.transport ?? "не подключена"].joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if info?.alsoPointing == true {
                        Text("Похоже на приёмник мыши")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.title3)
                    .foregroundStyle(selected ? Color.blue : Color.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Сочетания

struct ShortcutsPage: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Окна и рабочие столы") {
                FeatureToggle(
                    title: "Alt+Tab",
                    detail: "Переключатель приложений macOS остаётся открытым, пока держите Alt. Shift — в обратную сторону.",
                    combos: [KeyCombo(from: ["Alt", "Tab"], to: ["⌘", "Tab"])],
                    isOn: $model.settings.features.altTab
                )
                FeatureToggle(
                    title: "Рабочие столы",
                    detail: "Соседний рабочий стол, как в Windows 10/11.",
                    combos: [KeyCombo(from: ["Win", "Ctrl", "←"], to: ["⌃", "←"])],
                    isOn: $model.settings.features.winCtrlDesktops
                )
                FeatureToggle(
                    title: "Win — Spotlight",
                    detail: "Одиночное нажатие Win открывает поиск. С другими клавишами Win работает как ⌘.",
                    combos: [KeyCombo(from: ["Win"], to: ["⌘", "Space"])],
                    isOn: $model.settings.features.winAloneSpotlight
                )
            }

            Section("Язык") {
                FeatureToggle(
                    title: "Alt+Shift",
                    detail: "Левые или правые Alt+Shift без третьей клавиши меняют раскладку один раз.",
                    combos: [KeyCombo(from: ["Alt", "Shift"])],
                    isOn: $model.settings.features.altShiftLayout
                )
                FeatureToggle(
                    title: "Win+Space",
                    detail: "Смена раскладки без автоповтора.",
                    combos: [KeyCombo(from: ["Win", "Space"], to: ["⌃", "Space"])],
                    isOn: $model.settings.features.winSpaceLayout
                )
            }

            Section {
                FeatureToggle(
                    title: "Ctrl как Command",
                    detail: "Копировать, вставить, отменить, сохранить и другие. Ctrl+Y — повтор. Ctrl+Q/H/M не закрывают и не скрывают окна.",
                    combos: [
                        KeyCombo(from: ["Ctrl", "C"], to: ["⌘", "C"]),
                        KeyCombo(from: ["Ctrl", "Y"], to: ["⌘", "⇧", "Z"]),
                    ],
                    isOn: $model.settings.features.ctrlShortcuts
                )
                FeatureToggle(
                    title: "Ctrl+стрелки по словам",
                    detail: "Ctrl+←/→, Ctrl+Backspace и Ctrl+Delete работают со словами.",
                    combos: [KeyCombo(from: ["Ctrl", "←"], to: ["⌥", "←"])],
                    isOn: $model.settings.features.ctrlWordNavigation
                )
                FeatureToggle(
                    title: "Home и End",
                    detail: "Начало и конец строки.",
                    combos: [KeyCombo(from: ["Home"], to: ["⌘", "←"])],
                    isOn: $model.settings.features.homeEnd
                )
            } header: {
                Text("Текст")
            } footer: {
                Text("В терминалах Ctrl остаётся Ctrl: Ctrl+C прерывает команду, копирование — Ctrl+Shift+C/V.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(!model.settings.enabled)
    }
}

// MARK: - Мышь

struct MousePage: View {
    @Bindable var model: AppModel

    private var scroll: Binding<MosScrollSettings> { $model.settings.scroll }

    var body: some View {
        Form {
            if model.needsAccessibility {
                Section {
                    StatusLine(text: "Для масштаба и плавной прокрутки нужно разрешение «Универсальный доступ»", ok: false) {
                        Button("Разрешить") { model.requestAccessibility() }
                            .buttonStyle(.glassProminent)
                    }
                }
            }

            Section {
                FeatureToggle(
                    title: "Плавная прокрутка",
                    detail: "Колесо мыши прокручивает плавно, как трекпад. Трекпад не затрагивается.",
                    isOn: $model.settings.smoothScroll
                )
                if model.settings.smoothScroll && model.mosAppRunning {
                    StatusLine(text: "Запущен Mos — прокрутка CtrlAlt ждёт, пока он закроется, чтобы не сглаживать дважды", ok: false) {
                        Button("Закрыть Mos") { model.quitMosApp() }
                            .buttonStyle(.glassProminent)
                    }
                } else if model.smoothScrollActive {
                    StatusLine(text: "Работает", ok: true)
                }
                if model.settings.smoothScroll {
                    Toggle("По вертикали", isOn: scroll.smoothVertical.animation(Motion.snappy))
                    Toggle("По горизонтали", isOn: scroll.smoothHorizontal.animation(Motion.snappy))
                }
            } header: {
                Text("Прокрутка")
            } footer: {
                Text("Основано на Mos by Caldis (CC BY-NC 4.0). Отдельный Mos больше не нужен: настройки перенесены из него.")
                    .foregroundStyle(.secondary)
            }

            if model.settings.smoothScroll {
                Section("Направление") {
                    Toggle("Обратное направление колеса", isOn: scroll.reverse.animation(Motion.snappy))
                    if model.settings.scroll.reverse {
                        Toggle("По вертикали", isOn: scroll.reverseVertical)
                        Toggle("По горизонтали", isOn: scroll.reverseHorizontal)
                    }
                }

                Section {
                    ScrollSlider(title: "Шаг", value: scroll.step, range: 1...120, format: "%.0f")
                    ScrollSlider(title: "Скорость", value: scroll.speed, range: 1...10, format: "%.1f")
                    ScrollSlider(title: "Плавность", value: scroll.duration, range: 1...5, format: "%.2f")
                } header: {
                    Text("Тонкая настройка")
                } footer: {
                    HStack {
                        Text("Шаг — минимальная прокрутка за щелчок, плавность — как долго движение затухает.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("По умолчанию") {
                            withAnimation(Motion.smooth) {
                                var defaults = MosScrollSettings()
                                defaults.dash = model.settings.scroll.dash
                                defaults.toggle = model.settings.scroll.toggle
                                defaults.block = model.settings.scroll.block
                                model.settings.scroll = defaults
                            }
                        }
                        .buttonStyle(.glass)
                    }
                }

                Section {
                    ModifierPicker(title: "Ускорить прокрутку", selection: scroll.dash)
                    Toggle("Alt внешней клавиатуры тоже ускоряет", isOn: Binding(
                        get: { model.settings.scroll.dashAlternate != nil },
                        set: { model.settings.scroll.dashAlternate = $0 ? MosKeyCode.commandR : nil }
                    ))
                    ModifierPicker(title: "Прокручивать по горизонтали", selection: scroll.toggle)
                    ModifierPicker(title: "Без сглаживания", selection: scroll.block)
                } header: {
                    Text("Клавиши при прокрутке")
                } footer: {
                    Text("Держите клавишу и крутите колесо. Option, Shift и Control работают с любой стороны и на любой клавиатуре. Alt внешней клавиатуры — это правый ⌘, поэтому Win (левый ⌘) не ускоряет.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                FeatureToggle(
                    title: "Масштаб колесом",
                    detail: "Ctrl + колесо мыши увеличивает и уменьшает масштаб в Chrome, Safari и других приложениях.",
                    combos: [KeyCombo(from: ["Ctrl", "Колесо"], to: ["⌘", "+/−"])],
                    isOn: $model.settings.scrollZoom
                )
            } header: {
                Text("Масштаб")
            }
        }
        .formStyle(.grouped)
        .disabled(!model.settings.enabled)
        .animation(Motion.smooth, value: model.settings.smoothScroll)
        .animation(Motion.smooth, value: model.mosAppRunning)
        .animation(Motion.smooth, value: model.needsAccessibility)
    }
}

/// Ползунок с подписью и текущим значением.
struct ScrollSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var format: String

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                    .frame(minWidth: 180)
                Text(String(format: format, value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                    .contentTransition(.numericText(value: value))
                    .animation(Motion.snappy, value: value)
            }
        } label: {
            Text(title)
        }
    }
}

/// Выбор клавиши-модификатора для прокрутки.
struct ModifierPicker: View {
    var title: String
    @Binding var selection: UInt16?

    private static let options: [(code: UInt16?, title: String)] = [
        (nil, "Нет"),
        (MosKeyCode.shiftL, "⇧ Shift"),
        (MosKeyCode.optionL, "⌥ Option"),
        (MosKeyCode.commandL, "⌘ Command"),
        (MosKeyCode.controlL, "⌃ Control"),
    ]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Self.options, id: \.title) { option in
                Text(option.title).tag(option.code)
            }
            // Клавиша из Mos, которой нет в списке (например, правый Shift), остаётся выбранной.
            if let code = selection, !Self.options.contains(where: { $0.code == code }) {
                Text("Клавиша \(code)").tag(Optional(code))
            }
        }
    }
}

// MARK: - Karabiner

struct KarabinerPage: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            if !model.status.ready {
                Section {
                    KarabinerSetupSteps(model: model)
                } header: {
                    Text("Подготовка Karabiner")
                } footer: {
                    Text("CtrlAlt не перехватывает клавиши сам: это делает Karabiner-Elements. Если он уже установлен, CtrlAlt просто использует его.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Состояние") {
                row("Karabiner-Elements", ok: model.status.installed,
                    value: model.status.installed ? (model.status.version ?? "установлен") : "не установлен")
                row("Драйвер VirtualHIDDevice", ok: model.status.driverActive,
                    value: model.status.driverActive ? "активен" : "не активирован")
                row("Настройки karabiner.json", ok: model.status.configExists,
                    value: model.status.configExists ? "найдены" : "нет — откройте Karabiner один раз")
            }

            Section {
                HStack {
                    Button("Открыть Karabiner", systemImage: "gearshape.2") {
                        NSWorkspace.shared.open(Karabiner.appURL)
                    }
                    Button("EventViewer", systemImage: "waveform.path.ecg") {
                        NSWorkspace.shared.open(Karabiner.eventViewerURL)
                    }
                    Button("Бэкапы", systemImage: "clock.arrow.circlepath") {
                        try? FileManager.default.createDirectory(at: KarabinerConfig.backupDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(KarabinerConfig.backupDirectory)
                    }
                }
                .buttonStyle(.glass)
                .disabled(!model.status.installed)
            } footer: {
                Text("CtrlAlt меняет только свои правила в выбранном профиле и делает бэкап перед каждой записью. Остальные настройки Karabiner, включая F-клавиши, не трогает.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ title: String, ok: Bool, value: String) -> some View {
        LabeledContent {
            Text(value).foregroundStyle(.secondary)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? .green : .orange)
            }
        }
    }
}

// MARK: - О программе

struct AboutPage: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            AppIconImage(size: 110)
            Text("CtrlAlt").font(.largeTitle.weight(.semibold))
            Text("Версия \(model.version)").foregroundStyle(.secondary)
            Text("Windows-сочетания на внешней клавиатуре.\nВвод обрабатывает Karabiner-Elements, CtrlAlt управляет его правилами.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("Karabiner-Elements", systemImage: "safari") {
                    NSWorkspace.shared.open(Karabiner.downloadPage)
                }
                Button("Mos", systemImage: "safari") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Caldis/Mos")!)
                }
            }
            .buttonStyle(.glass)
            Text("Плавная прокрутка основана на Mos by Caldis (CC BY-NC 4.0).\nCtrlAlt — некоммерческий проект.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
