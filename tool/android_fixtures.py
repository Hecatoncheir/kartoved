"""Готовит вход Android-теста с двумя снимками, не включая их в релизный APK."""
import base64
from pathlib import Path

def photo(name):
    return base64.b64encode((Path("test/fixtures") / name).read_bytes()).decode("ascii")

Path("integration_test/generated_acceptance_test.dart").write_text(
    "import 'offline_test.dart' as suite;\nvoid main() => suite.runOfflineTests(\n"
    + f"'{photo('bouncers-beatdown.jpg')}',\n'{photo('bouncers-beatdown-ru.jpg')}',\n);\n", encoding="utf-8")
