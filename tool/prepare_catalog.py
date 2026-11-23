"""Сборка автономного каталога из официального комплекта ManaVault."""
import argparse
import gzip
import hashlib
import json
import re
import shutil
import sqlite3
import tempfile
import urllib.request
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
MODELS = ("detector.onnx", "embed.onnx", "search.onnx")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def printing_metadata(cache):
    headers = {"User-Agent": "Kartoved (github.com/Hecatoncheir/kartoved)", "Accept": "application/json"}
    req = urllib.request.Request("https://api.scryfall.com/bulk-data/all-cards", headers=headers)
    with urllib.request.urlopen(req, timeout=45) as source:
        url = json.load(source)["jsonl_download_uri"]
    target = cache / url.rsplit("/", 1)[1]
    if not target.exists():
        partial = target.with_suffix(".part")
        with urllib.request.urlopen(url, timeout=90) as source, partial.open("wb") as out:
            shutil.copyfileobj(source, out)
        partial.replace(target)
    return target


def enrich_printings(db, bulk):
    names = {name for (name,) in db.execute("SELECT DISTINCT name FROM editions")}
    terms = {(name, name.casefold()) for name in names}
    foil = []
    with gzip.open(bulk, "rt", encoding="utf-8") as stream:
        for line in stream:
            card = json.loads(line)
            if card.get("finishes") == ["foil"]:
                foil.append((card["id"],))
            if card.get("lang") == "ru":
                for face in [card, *card.get("card_faces", [])]:
                    alias = face.get("printed_name")
                    if alias and face.get("name") in names:
                        terms.add((face["name"], alias.casefold()))
    db.execute("CREATE TEMP TABLE foil_only(id TEXT PRIMARY KEY)")
    db.executemany("INSERT OR IGNORE INTO foil_only VALUES (?)", foil)
    db.execute("UPDATE editions SET foil=1 WHERE substr(id,1,36) IN (SELECT id FROM foil_only)")
    db.execute("CREATE TABLE search_names(name TEXT, term TEXT)")
    db.executemany("INSERT INTO search_names VALUES (?,?)", sorted(terms))
    db.execute("CREATE INDEX edition_name ON editions(name)")


def prepare_database(path, arts, editions, bulk):
    with sqlite3.connect(path) as db:
        db.executescript("""
            CREATE TABLE arts (idx INTEGER PRIMARY KEY, id TEXT, name TEXT);
            CREATE TABLE editions (art INTEGER, id TEXT, name TEXT, set_code TEXT, number TEXT, lang TEXT, foil INTEGER DEFAULT 0);
        """)
        for index, art in enumerate(arts):
            db.execute("INSERT INTO arts VALUES (?,?,?)", (index, art["id"], art["name"]))
            rows = editions.get(art["id"]) or [art]
            db.executemany("INSERT INTO editions(art,id,name,set_code,number,lang) VALUES (?,?,?,?,?,?)", (
                (index, row["id"], row["name"], row["set"], row.get("collector_number", ""), row["lang"])
                for row in rows
            ))
        db.execute("CREATE INDEX edition_art ON editions(art)")
        enrich_printings(db, bulk)
    db.close()


def prepare(version, source, destination):
    if not re.fullmatch(r"[a-zA-Z0-9._-]+", version):
        raise ValueError("Недопустимая версия")
    source.mkdir(parents=True, exist_ok=True)
    url = f"https://github.com/cfbender/manavault/releases/download/scanner-bundle-{version}/"

    def fetch(name):
        path = source / name
        if not path.exists():
            urllib.request.urlretrieve(url + name, path)
        return path

    meta = json.loads(fetch("manifest.json").read_bytes())
    if meta["version"] != version:
        raise ValueError("Версия локального кеша отличается")
    for name in (*MODELS, "arts.json", "printings.json"):
        if digest(fetch(name)) != meta["files"][name]["sha256"]:
            raise ValueError(f"Повреждён файл {name}")
    destination.mkdir(parents=True, exist_ok=True)
    arts = json.loads(fetch("arts.json").read_bytes())
    assert len(arts) == meta["gallery"]["arts"]
    bulk = printing_metadata(source)
    with tempfile.TemporaryDirectory() as temp:
        db_path = Path(temp) / "cards.sqlite"
        prepare_database(db_path, arts, json.loads(fetch("printings.json").read_bytes()), bulk)
        with db_path.open("rb") as src, (destination / "cards.sqlite.pack").open("wb") as packed:
            with gzip.GzipFile(fileobj=packed, filename="", mtime=0, mode="wb", compresslevel=6) as out:
                shutil.copyfileobj(src, out)
    for name in MODELS:
        shutil.copyfile(source / name, destination / name)
    files = {name: {"bytes": (destination / name).stat().st_size, "sha256": digest(destination / name)}
             for name in (*MODELS, "cards.sqlite.pack")}
    catalog = dict(schema=1, version=version + "-p1", upstreamVersion=version, printingMetadata=True, scryfallSnapshot=bulk.name,
                   created=meta["created"], count=len(arts),
                   constants=meta["constants"], searchMask=meta["search_mask"], files=files)
    (destination / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--source", type=Path)
    args = parser.parse_args()
    cache = args.source or PROJECT / ".dart_tool" / args.version
    prepare(args.version, cache, PROJECT / "assets" / "oracle")

