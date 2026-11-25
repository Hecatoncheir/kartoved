"""Выбирает файл в системных диалогах чистого эмулятора во время теста переноса."""

import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET


def shell(*args):
    return subprocess.check_output(
        ["adb", "-s", "emulator-5554", "shell", *args], text=True, timeout=20
    )


def dialog():
    focus = shell("dumpsys window | grep mCurrentFocus || true")
    if "documentsui" not in focus.lower():
        return focus.strip(), []
    result = shell("uiautomator", "dump", "/sdcard/kartoved-picker.xml")
    if "dumped" not in result.lower():
        return focus.strip(), []
    root = ET.fromstring(shell("cat", "/sdcard/kartoved-picker.xml"))
    return focus.strip(), [n.attrib for n in root.iter("node") if n.get("enabled") == "true"]


def tap(node):
    left, top, right, bottom = map(int, re.findall(r"\d+", node["bounds"]))
    shell("input", "tap", str((left + right) // 2), str((top + bottom) // 2))


def backup_entry(nodes):
    return next((n for n in nodes if n["class"] == "android.widget.TextView"
                 and re.fullmatch(r"kartoved-\d{4}-\d{2}-\d{2}(?:\.json)?", n["text"])), None)


def choose_file(tests, saving):
    last_focus = None
    while tests.poll() is None:
        time.sleep(2)
        focus, nodes = dialog()
        if focus != last_focus:
            print(f"Активное окно: {focus}", flush=True)
            last_focus = focus
        if focus.endswith("Application Not Responding: com.android.launcher3}"):
            # При холодном старте эмулятора Launcher иногда закрывает собой выбор файла.
            shell("am", "force-stop", "com.android.launcher3")
            continue
        save = next((n for n in nodes if n["text"].upper() == "SAVE"
                     or n["content-desc"].upper() == "SAVE"), None)
        if saving and save:
            tap(save)
            print("Файл сохранён через системный диалог", flush=True)
            return
        if saving or save:
            continue
        entry = backup_entry(nodes)
        if entry:
            tap(entry)
            print("Копия выбрана для восстановления", flush=True)
            return
        # Поставщики документов могут открывать пустой раздел «Недавние».
        downloads = next((n for n in nodes if n["text"] == "Downloads"), None)
        menu = next((n for n in nodes if n["content-desc"] == "Show roots"), None)
        if any(n["text"] == "Recent" for n in nodes) and (downloads or menu):
            tap(downloads or menu)
    raise SystemExit(tests.returncode or "Тест завершился до выбора файла")


if __name__ == "__main__":
    with subprocess.Popen(sys.argv[1:]) as process:
        try:
            choose_file(process, saving=True)
            choose_file(process, saving=False)
            sys.exit(process.wait())
        finally:
            if process.poll() is None:
                process.terminate()
