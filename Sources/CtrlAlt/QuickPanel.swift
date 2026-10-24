import AppKit
import SwiftUI

/// Панель в строке меню: большая кнопка включения, статус и быстрые переключатели.
struct QuickPanel: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var isOn: Bool { model.settings.enabled }

    var body: some View {
        VStack(spacing: 16) {
            header
            powerButton
            status
            if model.status.ready {
                tiles
            } else {
                KarabinerSetupCard(model: model) {
                    openSettingsWindow(openWindow, section: .karabiner, model: model)
                }
            }
            if let message = model.message, model.isError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(18)
        .frame(width: 320)
        .background(backdrop)
        .animation(.spring(duration: 0.4), value: isOn)
        .onAppear { model.refresh() }
    }

    // Мягкий цветной фон: стеклу нужно, что преломлять.
    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: isOn
                    ? [Color.blue.opacity(0.35), Color.purple.opacity(0.22), Color.clear]
                    : [Color.gray.opacity(0.18), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(isOn ? Color.cyan.opacity(0.25) : Color.clear)
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(y: -40)
        }
    }

    private var header: some View {
        HStack {
            Text("CtrlAlt")
                .font(.headline)
            Spacer()
            Button {
                openSettingsWindow(openWindow, model: model)
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Настройки")
        }
    }

    private var powerButton: some View {
        Button {
            model.settings.enabled.toggle()
        } label: {
            Image(systemName: "power")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .frame(width: 124, height: 124)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.blue).interactive() : .regular.interactive(), in: .circle)
        // Цвет под стеклом: включённое состояние видно и в неактивном окне.
        .background(
            Circle()
                .fill(LinearGradient(colors: [.cyan, .blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(isOn ? 0.85 : 0)
                .blur(radius: 6)
        )
        .shadow(color: isOn ? .blue.opacity(0.45) : .clear, radius: 22, y: 6)
        .padding(.vertical, 4)
        .help(isOn ? "Выключить Windows-сочетания" : "Включить Windows-сочетания")
    }

    private var status: some View {
        VStack(spacing: 4) {
            Text(!isOn ? "Выключено" : model.status.ready ? "Включено" : "Ждёт Karabiner")
                .font(.title2.weight(.semibold))
                .contentTransition(.opacity)
            Text(model.keyboardSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var tiles: some View {
        GlassEffectContainer(spacing: 10) {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    QuickTile(title: "Alt+Tab", symbol: "rectangle.stack.fill", isOn: $model.settings.features.altTab)
                    QuickTile(title: "Смена языка", symbol: "globe", isOn: $model.languageSwitching)
                }
                GridRow {
                    QuickTile(title: "Ctrl как ⌘", symbol: "command", isOn: $model.settings.features.ctrlShortcuts)
                    QuickTile(title: "Масштаб колесом", symbol: "plus.magnifyingglass", isOn: $model.settings.scrollZoom)
                }
            }
        }
        .disabled(!isOn)
        .opacity(isOn ? 1 : 0.55)
    }

    private var footer: some View {
        HStack {
            Button("Настройки…", systemImage: "slider.horizontal.3") {
                openSettingsWindow(openWindow, model: model)
            }
            .buttonStyle(.glass)
            Spacer()
            Button("Выйти", systemImage: "xmark") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.glass)
        }
        .controlSize(.regular)
    }
}

/// Плитка быстрого переключателя на стекле.
struct QuickTile: View {
    var title: String
    var symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(isOn ? Color.blue : Color.secondary.opacity(0.18), in: .circle)
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.blue.opacity(0.18)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 18))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
