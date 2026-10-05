#!/usr/bin/env python3
"""Capture immutable published v56 reference evidence, never rebuild old sources."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = ROOT / 'docs/qa/v057-reference'


def sha(value):
    return hashlib.sha256(value).hexdigest()


def digest(value):
    return sha(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('reference', type=Path)
    args = parser.parse_args()
    old = args.reference
    data = json.loads((old/'catalog.json').read_text())
    assert data['game_version'] == '0.56.0'
    assert 'source_tree_localization' not in data
    document = (old/'index.html').read_text()
    cards = dict(re.findall(r'(<article\b[^>]*id="([^"]+)"[^>]*>.*?</article>)', document, re.S))
    localized_rules = {'rules-source_'+k for k in ('spatial', 'recharge', 'mana_cost', 'flasks', 'critical', 'leech', 'fire_dot', 'faster_burn')}
    sections = {key: digest(value) for key, value in data.items()}
    result = {'origin': 'Frozen final v0.56 source snapshot, supplied by integration task',
              'game_version': data['game_version'], 'catalog_sha256': digest(data),
              'catalog_file_sha256': sha((old/'catalog.json').read_bytes()),
              'section_sha256': sections,
              'source_coverage_sha256': sha((old/'source-tree-coverage.json').read_bytes()),
              'image_sha256': {p.relative_to(old).as_posix(): sha(p.read_bytes()) for p in sorted(old.rglob('*.png'))},
              'card_ids': sorted(cards.values()),
              'unchanged_card_sha256': {key: sha(card.encode()) for card,key in cards.items()
                                       if not key.startswith('source_passives-') and key not in localized_rules},
              'allowed_localized_rule_cards': sorted(localized_rules),
              'template_sha256': {name: sha((old/name).read_bytes()) for name in ('reference.css','reference.js')}}
    target = QA/'v056-reference-baseline.json'
    assert not target.exists(), 'Do not replace frozen baseline evidence'
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(f'Captured all {len(sections)} old catalog sections, {len(cards)} cards and {len(result["image_sha256"])} original PNGs')


if __name__ == '__main__':
    main()
