# MosScroll

Плавная прокрутка мыши в CtrlAlt основана на исходном коде **Mos** — https://github.com/Caldis/Mos
Автор: Caldis. Copyright © 2017–2026 Caldis.

Лицензия Mos: **Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)** —
https://creativecommons.org/licenses/by-nc/4.0/

Эта часть CtrlAlt распространяется на тех же условиях: с указанием автора и **только в некоммерческих целях**.
Mos не связан с CtrlAlt и не одобрял его.

Исходная ревизия: `Caldis/Mos@8a2fd112e2af444c37ca5f65f42e9bd19c08a5c2` (ветка master, октябрь 2026).

## Взятые файлы

Из `Mos/ScrollCore/`: `ScrollCore.swift`, `ScrollPoster.swift`, `ScrollUtils.swift`, `ScrollEvent.swift`,
`ScrollPhase.swift`, `ScrollDispatchContext.swift`, `Interpolator.swift`, `ScrollFilter.swift`.
Из `Mos/Utils/`: `Interceptor.swift`.

## Изменения

- `Options.shared.scroll` заменён на `MosScroll.settings` (`MosSupport.swift`), значения по умолчанию те же.
- Удалены настройки для отдельных приложений (`Application`, allowlist): действуют только общие настройки.
- Удалена связь с кнопками мыши, сочетаниями и Logitech HID++ (`InputProcessor`, `ButtonUtils`,
  `ShortcutExecutor`, `ScrollActionPort`, `handleScrollHotkey`, `handleMosScrollAction`).
- Горячие клавиши прокрутки — только клавиши клавиатуры; смена окна отслеживается по PID цели прокрутки.
- `KeyCode`, `ScrollHotkey`, константы и расширения `CGEvent` заменены минимальными версиями в `MosSupport.swift`.
- Добавлен импорт настроек установленного Mos (`MosScrollSettings.importedFromMos()`).

Алгоритм сглаживания, фазы прокрутки, отправка событий и восстановление после сна не менялись.
