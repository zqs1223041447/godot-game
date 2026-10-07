#!/usr/bin/env python3
"""Bounded static/source/provenance check. No Godot or gameplay rerun."""
import hashlib
import importlib.util
import json
import math
import re
import subprocess
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = '1530db9'


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


merge = module('merge_fragment', QA/'merge-fragment.py')
builder = module('build_reference', ROOT/'tools/build_reference.py')


def sha(raw): return hashlib.sha256(raw).hexdigest()
def baseline(path): return subprocess.check_output(['git', 'show', BASE+':'+path], cwd=ROOT)


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.assets = [], [], []

    def handle_starttag(self, tag, pairs):
        attrs = dict(pairs)
        if 'id' in attrs: self.ids.append(attrs['id'])
        if 'href' in attrs: self.links.append(attrs['href'])
        if 'src' in attrs: self.assets.append(attrs['src'])


def main():
    raw = (REF/'catalog.json').read_text()
    oldraw = baseline('docs/reference/catalog.json').decode()
    data, old = json.loads(raw), json.loads(oldraw)
    fragment = json.loads((QA/'frost-chill-fragment.json').read_text())
    assert data == {**old, **fragment} and set(data)-set(old) == {'frost_guard_chill'}
    chill = data['frost_guard_chill']
    assert data['game_version'] == '0.87.0'
    assert data['save_version'] == chill['save_version'] == 50
    assert data['source_tree']['source_policy'] == chill['source_policy'] == 49
    assert chill['equipment_vocabulary'] == 46
    assert chill['policy'] == {'duration': 1.2, 'movement_speed_reduced': 0.25}
    assert chill['base_profile'] == {'windup_seconds': .9, 'radius': 90., 'recovery_seconds': 1.8, 'damage_multiplier': .8}
    assert chill['telegraph_policy']['chill_policy'] == chill['policy']
    assert chill['telegraph_policy']['profile'] == chill['base_profile']
    assert chill['source']['template_id'] == 'frost_guard' and chill['source']['wave'] == 4
    assert chill['start']['chill_policy'] == chill['event']['chill_policy'] == chill['recovery']['chill_policy'] == chill['policy']
    assert chill['start']['packet'] == chill['event']['packet'] == chill['recovery']['packet']
    assert chill['event']['packet']['tags'] == ['attack', 'area', 'hit']
    assert chill['start']['phase'] == 'windup' and chill['recovery']['phase'] == 'recovery'
    original_attack = old['monster_attacks']['locked_circle_cold']
    assert chill['base_profile'] == original_attack['profile']
    assert chill['event']['center'] == original_attack['example']['event']['center']
    roundtrip = []
    for key, value in original_attack['example']['event']['packet']['base'].items():
        current = chill['event']['packet']['base'][key]
        assert math.isclose(current, value, rel_tol=0, abs_tol=1e-12)
        if current != value: roundtrip.append({'field': 'new_snapshot.event.packet.base.'+key, 'historical': value, 'snapshot': current, 'absolute_difference': abs(value-current)})
    before, after = merge.spans(oldraw), merge.spans(raw)
    preserved_sections = []
    for key, (_, start, end) in before.items():
        if key == 'game_version': continue
        _, a, b = after[key]
        assert oldraw[start:end] == raw[a:b], key
        preserved_sections.append(key)
    html = (REF/'index.html').read_text()
    oldhtml = baseline('docs/reference/index.html').decode()
    cards = {key: value for value, key in re.findall(r'(<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>)', html, re.S)}
    old_cards = {key: value for value, key in re.findall(r'(<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>)', oldhtml, re.S)}
    intended = {'monsters-frost_guard', 'monster_attacks-locked_circle_cold', 'map_specials-frost_patrol'}
    assert set(cards)-set(old_cards) == {'rules-frost_guard_chill'} and set(old_cards) <= set(cards)
    identical, version_only = [], []
    for key, old_card in old_cards.items():
        current = cards[key]
        if key in intended:
            assert current != old_card and 'rules-frost_guard_chill' in current
            assert '25%' in current and '1.2 秒' in current
        elif current == old_card: identical.append(key)
        else:
            assert current == old_card.replace(old['game_version'], data['game_version']), key
            version_only.append(key)
    for map_id in old['exploration_maps']['maps']:
        assert cards['maps-'+map_id] == old_cards['maps-'+map_id], map_id
    assert cards['town_services-map_device'] == old_cards['town_services-map_device']
    original_diagram = builder.telegraph_diagram(original_attack)
    assert original_diagram in old_cards['monster_attacks-locked_circle_cold']
    assert original_diagram in cards['monster_attacks-locked_circle_cold']
    rule = cards['rules-frost_guard_chill']
    for text in ['raw_at', 'int/float', '当前结算窗口', '魔力先承伤', '过量伤害不计', '0.36', '175', 'schema50', '结界', '不被结界主动清除', '不追加伤害']:
        assert text in rule, text
    page, oldpage = Page(), Page()
    page.feed(html); oldpage.feed(oldhtml)
    assert len(page.ids) == len(set(page.ids)) and set(oldpage.ids) <= set(page.ids)
    for link in page.links:
        if link.startswith('#'): assert link[1:] in page.ids, link
        elif not re.match(r'^[a-z]+:', link): assert (REF/link.split('#')[0]).resolve().exists(), link
    for asset in page.assets:
        if not re.match(r'^[a-z]+:', asset): assert (REF/asset).is_file(), asset
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE, '--', 'docs/reference'], cwd=ROOT, text=True).splitlines()
    protected = []
    for path in paths:
        if path in ['docs/reference/catalog.json', 'docs/reference/index.html']: continue
        assert (ROOT/path).read_bytes() == baseline(path), path
        protected.append(path)
    assert {str(p.relative_to(ROOT)) for p in REF.rglob('*.png')} == {p for p in paths if p.endswith('.png')}
    provenance = {}
    for key in ['actual_main_report', 'actual_main_run', 'actual_main_inputs']:
        source = chill[key]
        assert sha((ROOT/source['path']).read_bytes()) == source['sha256']
        provenance[key] = source
    accepted = json.loads((ROOT/chill['actual_main_report']['path']).read_text())
    run = json.loads((ROOT/chill['actual_main_run']['path']).read_text())
    inputs = json.loads((ROOT/chill['actual_main_inputs']['path']).read_text())
    assert accepted['checks'] == chill['actual_main_checks'] > 0 and accepted['failures'] == 0
    assert run['exit_code'] == 0 and run['error_logged'] is False and run['timed_out'] is False
    for path, digest in inputs.items():
        assert sha((ROOT/path).read_bytes()) == digest, path
    unchanged_authorities = []
    for path in chill['sources'].values():
        if path in inputs: continue
        assert path == 'scripts/monsters/telegraph_profiles.gd', path
        assert (ROOT/path).read_bytes() == baseline(path), path
        unchanged_authorities.append(path)
    art = json.loads((REF/'art/manifest.json').read_text())
    assert builder.build(data, art) == html
    assert builder.build(old, art) == oldhtml, 'Builder must preserve every old card when the new fragment is absent'
    proof = {'baseline_commit': BASE, 'preserved_raw_top_level_count': len(preserved_sections),
             'preserved_raw_top_level_sections': preserved_sections, 'byte_identical_card_count': len(identical),
             'only_game_version_label_changed': version_only, 'replaced_current_cards': sorted(intended),
             'new_current_cards': ['rules-frost_guard_chill'], 'preserved_anchor_count': len(oldpage.ids),
             'all_four_map_cards_and_map_device_byte_identical': True,
             'original_frost_damage_diagram_byte_identical': True,
             'all_old_damage_examples_raw_tokens_preserved': True,
             'new_snapshot_only_float_roundtrip_differences': roundtrip,
             'protected_file_count': len(protected), 'protected_png_count': sum(p.endswith('.png') for p in protected),
             'coverage_and_png_bytes_preserved': True, 'no_new_pngs': True,
             'actual_main_provenance': provenance, 'actual_main_checks': accepted['checks'],
             'actual_main_failures': 0, 'main_source_fingerprints_match': True,
             'additional_authorities_byte_equal_v086': unchanged_authorities,
             'build_matches': True, 'builder_backward_compatible_with_entire_old_catalog': True,
             'all_local_links_resolve': True,
             'scope': 'Static/source/provenance only. No gameplay rerun, full export, map regeneration, native F8 visual or release validation.'}
    with (QA/'preservation.json').open('x') as handle:
        json.dump(proof, handle, ensure_ascii=False, indent=2); handle.write('\n')
    print(json.dumps({key: value for key, value in proof.items() if key != 'preserved_raw_top_level_sections'}, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()
