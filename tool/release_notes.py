"""Извлекает раздел CHANGELOG для версии из тега."""
import re
import sys
from pathlib import Path

tag, output = sys.argv[1:]
if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?", tag):
    raise SystemExit("Ожидается тег vX.Y.Z")
version = tag[1:]
spec = Path("pubspec.yaml").read_text(encoding="utf-8")
if not re.search(r"^version: " + re.escape(version) + r"\+\d+$", spec, re.M):
    raise SystemExit("Версия тега отличается от pubspec.yaml")
log = Path("CHANGELOG.md").read_text(encoding="utf-8")
section = re.search(r"^## " + re.escape(version) + r"[ \t]*\n(.*?)(?=^## |\Z)", log, re.M | re.S)
if not section or not section[1].strip():
    raise SystemExit("У версии отсутствует описание в CHANGELOG.md")
Path(output).write_text(section[1].strip() + "\n", encoding="utf-8")
