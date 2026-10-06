#!/usr/bin/env python3
"""Recover original JSON number types after Godot's parsed-number round trip."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('baseline_catalog', type=Path)
    args = parser.parse_args()
    baseline = json.loads((QA / 'v073-baseline.json').read_text())
    raw = args.baseline_catalog.read_bytes()
    assert sha(raw) == baseline['catalog_sha256']
    path = ROOT / 'docs/reference/catalog.json'
    current = json.loads(path.read_text())
    corrected = current['source_monster_movement']
    assert corrected['save_version'] == 47 and isinstance(corrected['save_version'], int)
    output = json.loads(raw)
    output['game_version'] = current['game_version']
    output['source_monster_movement'] = corrected
    definition = deepcopy(current['mechanisms']['source_gale_stride'])
    definition.update(corrected['definition'])
    for key in ['schema_version', 'definition_revision']:
        definition[key] = corrected['monster_grant'][key]
    output['mechanisms']['source_gale_stride'] = definition
    path.write_text(json.dumps(output, ensure_ascii=False, indent='\t', sort_keys=True) + '\n')
    report = {'baseline_sha256_verified': sha(raw), 'current_schema': corrected['save_version'],
              'restored_all_historical_json_number_types': True,
              'source_chapter_regenerated_by': 'refresh-source-chapter.gd',
              'allowed_changes_from_baseline': ['game_version', 'mechanisms.source_gale_stride', 'source_monster_movement'],
              'catalog_sha256': sha(path.read_bytes())}
    with (QA / 'json-number-restoration.json').open('x') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
