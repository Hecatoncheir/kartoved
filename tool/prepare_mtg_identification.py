"""Собирает ONNX-модель MTG Identification и её индекс для Картоведа."""

import argparse
import gzip
import hashlib
import json
import shutil
import sqlite3
import urllib.request
from collections import defaultdict
from pathlib import Path

import numpy as np
import onnx
from onnx import TensorProto, compose, helper, numpy_helper


ROOT = Path(__file__).resolve().parents[1]
REVISION = "653d88d94b2beb31a7894561e7c6b26f589a3861"
SOURCE = (
    "https://huggingface.co/dhvazquez/mtg_card_identification_embeddings/resolve/"
    f"{REVISION}/20260521-044732/"
)
EMBEDDER = "onnx/mtg_embed_fp32.onnx"
GALLERY = "gallery_val.npz"
POSE = "exports/mtg_4kp_s_r4b.onnx"
POSE_REVISION = "ef6d7912e7e2db79ce24976cb3ea84984e43721a"
POSE_SOURCE = f"https://huggingface.co/dhvazquez/mtg_card_pose_estimation/resolve/{POSE_REVISION}/"
CHECKSUMS = {
    EMBEDDER: "fa092cdc8a25b0f3b80ee0ec0580fc9b4e0dc03bb49f9b7ffa43b83b88672ed2",
    GALLERY: "0eb38edd4a238b9c97dbc2bd5f77150fd911edd551823a2d5cd027168c7f36e7",
    POSE: "3d33788e992e4882e37b1d2307994942552413092fdebaf998728cdbda4b5a99",
}
WIDTH, HEIGHT, DIMENSIONS = 320, 448, 256


def artifact(cache, name, source=SOURCE):
    path = cache / Path(name).name
    if not path.exists():
        partial = path.with_suffix(".part")
        with urllib.request.urlopen(source + name, timeout=90) as response, partial.open("wb") as out:
            shutil.copyfileobj(response, out)
        partial.replace(path)
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != CHECKSUMS[name]:
        raise ValueError(f"Контрольная сумма {path.name} отличается от опубликованной")
    return path


def gallery(path):
    with sqlite3.connect(":memory:") as db:
        db.deserialize(gzip.decompress((ROOT / "assets/oracle/cards.sqlite.pack").read_bytes()))
        representative = dict(db.execute("SELECT idx, id FROM arts"))
        art_by_printing = dict(db.execute("SELECT id, art FROM editions"))

    # Суффикс класса начинается с UUID выпуска Scryfall. Группировка по
    # иллюстрации сохраняет выбор языка и выпуска из каталога Картоведа.
    groups = defaultdict(list)
    with np.load(path, allow_pickle=False) as data:
        for index, label in enumerate(data["labels"]):
            printing = label.split("__", 1)[1].split("_", 1)[0]
            art = art_by_printing.get(printing)
            if art is not None:
                groups[art].append(index)
        ordered = sorted(groups)
        vectors = data["embeddings"]
        centers = np.stack([vectors[groups[art]].mean(axis=0) for art in ordered])

    if len(ordered) < 5 or centers.shape[1] != DIMENSIONS or not np.isfinite(centers).all():
        raise ValueError("Некорректная галерея MTG Identification")
    centers /= np.linalg.norm(centers, axis=1, keepdims=True)
    return [representative[art] for art in ordered], centers.T.copy()


def recognition_graph(path, centers):
    embedder = compose.add_prefix(onnx.load(path), "mtg_")
    nodes = []
    initializers = list(embedder.graph.initializer)

    def constant(name, value):
        initializers.append(numpy_helper.from_array(np.asarray(value), name))
        return name

    def node(op, inputs, output, **attributes):
        nodes.append(helper.make_node(op, inputs, [output], **attributes))
        return output

    x = constant("x", np.linspace(0, 1, WIDTH, dtype=np.float32).reshape(1, WIDTH, 1))
    y = constant("y", np.linspace(0, 1, HEIGHT, dtype=np.float32).reshape(HEIGHT, 1, 1))
    corners = [node("Gather", ["quad", constant(f"corner_{i}", np.int64(i))], name)
               for i, name in enumerate(("tl", "tr", "br", "bl"))]

    def lerp(a, b, fraction, label):
        delta = node("Sub", [b, a], f"{label}_delta")
        offset = node("Mul", [delta, fraction], f"{label}_offset")
        return node("Add", [a, offset], label)

    left = lerp(corners[0], corners[3], y, "left")
    right = lerp(corners[1], corners[2], y, "right")
    grid = lerp(left, right, x, "pixels")
    shape = node("Shape", ["scene"], "scene_shape")
    size = node("Gather", [shape, constant("size_axis", np.array([1, 0], dtype=np.int64))], "size")
    size_f = node("Cast", [size], "size_f", to=TensorProto.FLOAT)
    one = constant("one", np.float32(1))
    extent = node("Sub", [size_f, one], "extent")
    unit = node("Div", [grid, extent], "unit")
    doubled = node("Mul", [unit, constant("two", np.float32(2))], "doubled")
    normalized = node("Sub", [doubled, one], "normalized_grid")
    batch_axis = constant("batch_axis", np.array([0], dtype=np.int64))
    grid4d = node("Unsqueeze", [normalized, batch_axis], "grid_4d")

    rgb = node("Slice", ["scene", constant("rgb_start", np.array([0], dtype=np.int64)),
                         constant("rgb_end", np.array([3], dtype=np.int64)),
                         constant("channel_axis", np.array([2], dtype=np.int64))], "rgb")
    pixels = node("Cast", [rgb], "float_rgb", to=TensorProto.FLOAT)
    chw = node("Transpose", [pixels], "chw", perm=[2, 0, 1])
    batch = node("Unsqueeze", [chw, batch_axis], "batch")
    crop = node("GridSample", [batch, grid4d], "crop", align_corners=1, padding_mode="border")
    mean = np.array([.485, .456, .406], dtype=np.float32).reshape(1, 3, 1, 1)
    std = np.array([.229, .224, .225], dtype=np.float32).reshape(1, 3, 1, 1)
    scaled = node("Mul", [crop, constant("scale", 1 / (255 * std))], "scaled")
    node("Sub", [scaled, constant("mean", mean / std)], embedder.graph.input[0].name)
    nodes.extend(embedder.graph.node)
    similarity = node("MatMul", [embedder.graph.output[0].name, constant("gallery", centers)], "similarity")
    nodes.append(helper.make_node("TopK", [similarity, constant("k", np.array([5], dtype=np.int64))],
                                  ["scores", "indices"], axis=-1))
    graph = helper.make_graph(
        nodes, "Kartoved MTG Identification",
        [helper.make_tensor_value_info("scene", TensorProto.UINT8, ["height", "width", 4]),
         helper.make_tensor_value_info("quad", TensorProto.FLOAT, [4, 2])],
        [helper.make_tensor_value_info("scores", TensorProto.FLOAT, [1, 5]),
         helper.make_tensor_value_info("indices", TensorProto.INT64, [1, 5])],
        initializer=initializers,
    )
    model = helper.make_model(graph, opset_imports=embedder.opset_import, ir_version=embedder.ir_version)
    onnx.checker.check_model(model)
    return model


def pose_graph(path):
    pose = compose.add_prefix(onnx.load(path), "pose_")
    side = 640
    constants = {
        "rgb": np.array([0, 1, 2], dtype=np.int64),
        "batch": np.array([0], dtype=np.int64),
        "scale": np.float32(1 / 255),
        "side": np.float32(side),
    }
    node = helper.make_node
    graph = helper.make_graph(
        [
            node("Gather", ["scene", "rgb"], ["rgb_pixels"], axis=2),
            node("Cast", ["rgb_pixels"], ["pixels"], to=TensorProto.FLOAT),
            node("Transpose", ["pixels"], ["channels"], perm=[2, 0, 1]),
            node("Unsqueeze", ["channels", "batch"], ["input_batch"]),
            node("Mul", ["input_batch", "scale"], ["pose_image"]),
            *pose.graph.node,
            node("Squeeze", ["pose_scores", "batch"], ["logits"]),
            node("ArgMax", ["logits"], ["winner"], axis=0, keepdims=0),
            node("Gather", ["logits", "winner"], ["logit"]),
            node("Sigmoid", ["logit"], ["score"]),
            node("Squeeze", ["pose_keypoints", "batch"], ["keypoints"]),
            node("Gather", ["keypoints", "winner"], ["corners"]),
            node("Mul", ["corners", "side"], ["quad"]),
        ],
        "Kartoved MTG Card Pose",
        [helper.make_tensor_value_info("scene", TensorProto.UINT8, [side, side, 4])],
        [helper.make_tensor_value_info("score", TensorProto.FLOAT, []),
         helper.make_tensor_value_info("quad", TensorProto.FLOAT, [4, 2])],
        initializer=[*pose.graph.initializer,
                     *(numpy_helper.from_array(value, name) for name, value in constants.items())],
    )
    model = helper.make_model(graph, opset_imports=pose.opset_import, ir_version=pose.ir_version)
    onnx.checker.check_model(model)
    return model


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".dart_tool/mtg-model")
    parser.add_argument("--pose-only", action="store_true", help="Собрать только модель границ карты")
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    output = ROOT / "assets/mtg_identification"
    output.mkdir(parents=True, exist_ok=True)
    onnx.save(pose_graph(artifact(args.cache, POSE, POSE_SOURCE)), output / "pose.onnx")
    if args.pose_only:
        return
    ids, vectors = gallery(artifact(args.cache, GALLERY))
    model = recognition_graph(artifact(args.cache, EMBEDDER), vectors)
    onnx.save(model, output / "recognize.onnx")
    (output / "printings.json").write_text(json.dumps(ids, separators=(",", ":")), encoding="utf-8")
    print(f"Совпадающих с каталогом иллюстраций: {len(ids)}")


if __name__ == "__main__":
    main()
