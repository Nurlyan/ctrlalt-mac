"""Генерирует правила Karabiner для KD83A (0416:7472): Windows Alt+Tab, Alt+Shift
и остальные Windows-сочетания из старого бэкапа.

Идея: левый Alt на KD83A, пока он удерживается, нажимает и держит Command.
Tab при удержанном Alt — это обычный Command+Tab, и переключатель macOS
остаётся открытым, пока Alt не отпущен. Остальные сочетания с левым Alt
переводятся обратно в Option, чтобы Alt+Q не превращался в Command+Q.
Левый Alt + левый Shift без третьей клавиши и Win+Space отправляют Ctrl+Space
(системная «предыдущая раскладка»). Одиночный Win открывает Spotlight.

Запуск: python3 make_alt_tab_rule.py [старый_бэкап.json] > kd83a-alt-tab.json
Без аргумента выводится только правило Alt+Tab/Alt+Shift.
"""
import json
import string
import sys

DEVICE = {
    "type": "device_if",
    "identifiers": [{"vendor_id": 1046, "product_id": 29810, "is_keyboard": True}],
}
ALT_HELD = "kd83a_alt_held"
SWITCHER = "kd83a_alt_tab_active"


def var_if(name, value):
    return {"type": "variable_if", "name": name, "value": value}


def set_var(name, value):
    return {"set_variable": {"name": name, "value": value}}


# Клавиши, которые с левым Alt (вне переключателя) должны давать Option+клавиша.
# F-клавиши не трогаем, чтобы не мешать их текущей настройке.
BACK_TO_OPTION = (
    list(string.ascii_lowercase)
    + [str(d) for d in range(10)]
    + [
        "hyphen", "equal_sign", "open_bracket", "close_bracket", "backslash",
        "semicolon", "quote", "comma", "period", "slash", "grave_accent_and_tilde",
        "return_or_enter", "delete_or_backspace", "delete_forward", "spacebar", "escape",
        "left_arrow", "right_arrow", "up_arrow", "down_arrow",
        "home", "end", "page_up", "page_down",
    ]
)

SWITCH_LAYOUT = [{"key_code": "spacebar", "modifiers": ["left_control"]}]
ALONE_TIMEOUT = {"basic.to_if_alone_timeout_milliseconds": 1000}

manipulators = [
    # Shift↓ затем Alt↓: Alt всё равно держит Command (для Shift+Alt+Tab),
    # а отпускание Alt без третьей клавиши меняет раскладку.
    {
        "type": "basic",
        "from": {"key_code": "left_option", "modifiers": {"mandatory": ["left_shift"], "optional": ["caps_lock"]}},
        "to": [set_var(ALT_HELD, 1), {"key_code": "left_command", "modifiers": ["left_shift"]}],
        "to_if_alone": SWITCH_LAYOUT,
        "to_after_key_up": [set_var(ALT_HELD, 0), set_var(SWITCHER, 0)],
        "conditions": [DEVICE],
        "parameters": ALONE_TIMEOUT,
    },
    # Alt↓ затем Shift↓: отпускание Shift без третьей клавиши меняет раскладку.
    # В открытом переключателе Shift работает как обычно (обратный проход).
    {
        "type": "basic",
        "from": {"key_code": "left_shift", "modifiers": {"mandatory": ["left_command"], "optional": ["caps_lock"]}},
        "to": [{"key_code": "left_shift", "modifiers": ["left_command"]}],
        "to_if_alone": SWITCH_LAYOUT,
        "conditions": [DEVICE, var_if(ALT_HELD, 1), var_if(SWITCHER, 0)],
        "parameters": ALONE_TIMEOUT,
    },
    # Первый и последующие Tab при удержанном Alt: Command уже зажат,
    # отмечаем, что переключатель открыт (optional any сохраняет Command и Shift).
    {
        "type": "basic",
        "from": {"key_code": "tab", "modifiers": {"optional": ["any"]}},
        "to": [set_var(SWITCHER, 1), {"key_code": "tab"}],
        "conditions": [DEVICE, var_if(ALT_HELD, 1)],
    },
    # Левый Alt: держим Command до отпускания, затем сбрасываем состояние.
    {
        "type": "basic",
        "from": {"key_code": "left_option", "modifiers": {"optional": ["any"]}},
        "to": [set_var(ALT_HELD, 1), {"key_code": "left_command"}],
        "to_after_key_up": [set_var(ALT_HELD, 0), set_var(SWITCHER, 0)],
        "conditions": [DEVICE],
    },
]

# Alt+клавиша вне переключателя → Option+клавиша.
for key in BACK_TO_OPTION:
    manipulators.append({
        "type": "basic",
        "from": {"key_code": key, "modifiers": {"mandatory": ["left_command"], "optional": ["any"]}},
        "to": [{"key_code": key, "modifiers": ["left_option"]}],
        "conditions": [DEVICE, var_if(ALT_HELD, 1), var_if(SWITCHER, 0)],
    })

manipulators += [
    # Win+Space → Ctrl+Space (смена раскладки), один раз на нажатие без автоповтора.
    {
        "type": "basic",
        "from": {"key_code": "spacebar", "modifiers": {"mandatory": ["left_command"], "optional": ["caps_lock"]}},
        "to": [{**SWITCH_LAYOUT[0], "repeat": False}],
        "conditions": [DEVICE, var_if(ALT_HELD, 0)],
    },
    # Одиночный Win → Spotlight (Command+Space); с другими клавишами Win остаётся Command.
    {
        "type": "basic",
        "from": {"key_code": "left_command", "modifiers": {"optional": ["any"]}},
        "to": [{"key_code": "left_command"}],
        "to_if_alone": [{"key_code": "spacebar", "modifiers": ["left_command"]}],
        "conditions": [DEVICE],
        "parameters": ALONE_TIMEOUT,
    },
]

rules = [{
    "description": "KD83A 0416:7472 — Windows Alt+Tab, Alt+Shift, Win",
    "manipulators": manipulators,
}]


def is_replaced(m):
    """Старые манипуляторы, которые заменены правилом выше: левые Alt+Shift и Alt+Tab."""
    key = m["from"].get("key_code")
    mandatory = m["from"].get("modifiers", {}).get("mandatory", [])
    return key in ("left_shift", "left_option", "tab") and "option" in mandatory or (
        key == "left_option" and "shift" in mandatory
    )


def adapt(m):
    """Правки старых Ctrl-сочетаний: Ctrl+Y — повтор, Ctrl+Q/H/M и Ctrl+Shift+Q остаются обычным Ctrl."""
    key = m["from"].get("key_code")
    mandatory = m["from"].get("modifiers", {}).get("mandatory", [])
    if mandatory == ["control"] and key in ("q", "h", "m"):
        return None
    if mandatory == ["control", "shift"] and key == "q":
        return None
    if mandatory == ["control"] and key == "y":
        return {**m, "to": [{"key_code": "z", "modifiers": ["left_command", "left_shift"]}]}
    return m


if len(sys.argv) > 1:
    old = json.load(open(sys.argv[1]))
    old_rule = next(
        r for p in old["profiles"] for r in p.get("complex_modifications", {}).get("rules", [])
        if r.get("description", "").startswith("KD83A 0416:7472")
    )
    rules.append({
        "description": "KD83A 0416:7472 — Windows Ctrl-сочетания, Home/End, правые Alt+Shift",
        "manipulators": [
            adapt(m) for m in old_rule["manipulators"] if not is_replaced(m) and adapt(m) is not None
        ],
    })

print(json.dumps({"title": "KD83A Windows", "rules": rules}, ensure_ascii=False, indent=2))
