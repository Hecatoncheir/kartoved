"""Готовит переводы названий для карт из автономного каталога."""

import argparse
import gzip
import json
import sqlite3
from collections import defaultdict
from pathlib import Path


ORACLE = Path(__file__).resolve().parents[1] / 'assets' / 'oracle'


def prepare(bulk, catalog, output):
    with sqlite3.connect(':memory:') as db:
        db.deserialize(gzip.decompress(catalog.read_bytes()))
        names = {name for (name,) in db.execute('SELECT DISTINCT name FROM editions')}

    aliases = defaultdict(set)
    with gzip.open(bulk, 'rt', encoding='utf-8') as source:
        for line in source:
            card = json.loads(line)
            for face in (card, *card.get('card_faces', [])):
                name, printed = face.get('name'), face.get('printed_name')
                if name in names and printed and printed != name:
                    term = printed.lower().replace('’', "'").replace('‘', "'")
                    aliases[name].add(' '.join(term.split()))

    rows = [
        f'  {json.dumps(name, ensure_ascii=False)}: {json.dumps(sorted(terms), ensure_ascii=False)}'
        for name, terms in sorted(aliases.items())
    ]
    output.write_text('{\n' + ',\n'.join(rows) + '\n}\n', encoding='utf-8', newline='\n')
    print(f'Карт с переводами: {len(rows)}. Названий: {sum(map(len, aliases.values()))}.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bulk', type=Path)
    parser.add_argument('--catalog', type=Path, default=ORACLE / 'cards.sqlite.pack')
    parser.add_argument('--output', type=Path, default=ORACLE / 'scan_names.json')
    args = parser.parse_args()
    prepare(args.bulk, args.catalog, args.output)
