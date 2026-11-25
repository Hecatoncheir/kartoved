"""Проверяет файлы автономного сканера после упаковки Android."""
import hashlib
import json
import sys
import zipfile
from pathlib import Path

root = "assets/flutter_assets/assets/oracle/"
with zipfile.ZipFile(Path(sys.argv[1])) as apk:
    manifest = json.loads(apk.read(root + "catalog.json"))
    for name, spec in manifest["files"].items():
        info = apk.getinfo(root + name)
        if info.file_size != spec["bytes"]:
            raise ValueError(f"Размер {name} отличается от манифеста")
        with apk.open(info) as source:
            if hashlib.file_digest(source, "sha256").hexdigest() != spec["sha256"]:
                raise ValueError(f"Контрольная сумма {name} отличается от манифеста")
    if not any(name.endswith("/libonnxruntime.so") for name in apk.namelist()):
        raise ValueError("В APK отсутствует ONNX Runtime")
    for asset in map(Path, (
        "assets/mtg_identification/recognize.onnx",
        "assets/mtg_identification/printings.json",
        "assets/paddleocr/title.onnx",
        "assets/paddleocr/alphabet.json",
    )):
        with asset.open("rb") as source:
            expected = hashlib.file_digest(source, "sha256").digest()
        with apk.open("assets/flutter_assets/" + asset.as_posix()) as source:
            actual = hashlib.file_digest(source, "sha256").digest()
        if actual != expected:
            raise ValueError(f"Файл распознавания в APK отличается от исходного: {asset}")
print(manifest["version"], manifest["count"])
