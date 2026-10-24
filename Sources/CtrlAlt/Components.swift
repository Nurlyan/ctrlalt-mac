import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general, keyboard, shortcuts, mouse, karabiner, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "Основные"
        case .keyboard: "Клавиатура"
        case .shortcuts: "Сочетания"
        case .mouse: "Мышь"
        case .karabiner: "Karabiner"
        case .about: "О программе"
        }
    }

    var symbol: String {
        switch self {
        case .general: "power"
        case .keyboard: "keyboard"
        case .shortcuts: "command"
        case .mouse: "computermouse.fill"
        case .karabiner: "gearshape.2.fill"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .general: .green
        case .keyboard: .blue
        case .shortcuts: .purple
        case .mouse: .orange
        case .karabiner: .gray
        case .about: .teal
        }
    }
}

/// Цветной значок в скруглённом квадрате, как в «Системных настройках».
struct IconBadge: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color.mix(with: .white, by: 0.15), color], startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: size * 0.26)
            )
    }
}

/// Клавиша: «Ctrl», «Tab», «⌘».
struct KeyCap: View {
    var label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 18)
            .background(.quaternary, in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator, lineWidth: 0.5))
    }
}

/// Сочетание из нескольких клавиш: Ctrl + C → ⌘ + C.
struct KeyCombo: View {
    var from: [String]
    var to: [String]? = nil

    var body: some View {
        HStack(spacing: 3) {
            keys(from)
            if let to {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
                keys(to)
            }
        }
    }

    private func keys(_ labels: [String]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                KeyCap(label: label)
            }
        }
    }
}

/// Строка-переключатель с подписью и примерами сочетаний.
struct FeatureToggle: View {
    var title: String
    var detail: String
    var combos: [KeyCombo] = []
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !combos.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(combos.enumerated()), id: \.offset) { _, combo in combo }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 3)
        }
        .toggleStyle(.switch)
    }
}

/// Строка состояния: значок «всё хорошо / внимание», текст и необязательная кнопка.
struct StatusLine<Action: View>: View {
    var text: String
    var ok: Bool
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            action
        }
    }
}

extension StatusLine where Action == EmptyView {
    init(text: String, ok: Bool) {
        self.init(text: text, ok: ok) { EmptyView() }
    }
}

/// Иконка приложения из бандла (в debug-сборке без бандла — общая иконка приложения).
struct AppIconImage: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable()
            .frame(width: size, height: size)
    }
}

@MainActor
func openSettingsWindow(_ openWindow: OpenWindowAction, section: SettingsSection? = nil, model: AppModel) {
    if let section { model.section = section }
    openWindow(id: "settings")
    NSApp.activate()
}
