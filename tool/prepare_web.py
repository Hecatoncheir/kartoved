"""Копирует зафиксированные браузерные зависимости в ресурсы Flutter."""

import argparse
import gzip
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NODE = ROOT / "tool" / "web" / "node_modules"
WEB = ROOT / "web"
NATIVE = ROOT / "android" / "app" / "src" / "main"


def copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def prepare():
    runtime = WEB / "runtime"
    ort = NODE / "onnxruntime-web"
    for name in ("ort.wasm.min.mjs", "ort-wasm-simd-threaded.mjs", "ort-wasm-simd-threaded.wasm"):
        copy(ort / "dist" / name, runtime / "ort" / name)
    copy(ROOT / "assets" / "licenses" / "ONNXRuntime.txt", runtime / "ort" / "LICENSE")
    copy(ROOT / "assets" / "licenses" / "ONNXRuntimeThirdParty.txt", runtime / "ort" / "ThirdPartyNotices.txt")

    ocr = NODE / "tesseract.js"
    for name in ("tesseract.min.js", "tesseract.min.js.LICENSE.txt", "worker.min.js", "worker.min.js.LICENSE.txt"):
        copy(ocr / "dist" / name, runtime / "ocr" / name)
    core = NODE / "tesseract.js-core"
    for stem in ("tesseract-core-lstm", "tesseract-core-simd-lstm"):
        for suffix in (".wasm", ".wasm.js"):
            copy(core / f"{stem}{suffix}", runtime / "ocr" / "core" / f"{stem}{suffix}")
    copy(core / "LICENSE", runtime / "ocr" / "core" / "LICENSE")

    data = runtime / "ocr" / "data"
    data.mkdir(parents=True, exist_ok=True)
    for language in ("eng", "rus"):
        source = NATIVE / "assets" / "tessdata" / f"{language}.traineddata"
        (data / f"{language}.traineddata.gz").write_bytes(gzip.compress(source.read_bytes(), mtime=0))
    for name in ("card_added.wav", "card_found.wav", "card_review.wav"):
        copy(NATIVE / "res" / "raw" / name, runtime / name)


def seal(build, build_id):
    worker = build / "sw.js"
    worker.write_text(worker.read_text(encoding="utf-8").replace("__KARTOVED_BUILD__", build_id), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--seal", nargs=2, metavar=("BUILD_DIR", "BUILD_ID"))
    args = parser.parse_args()
    if args.seal:
        seal(Path(args.seal[0]), args.seal[1])
    else:
        prepare()
