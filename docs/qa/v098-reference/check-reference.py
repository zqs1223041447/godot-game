#!/usr/bin/env python3
"""Bounded v98 data, links, search and byte preservation; no Godot execution."""
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import struct
import subprocess
from html.parser import HTMLParser

ROOT = Path(__file__).resolve().parents[3]
QA = Path(__file__).resolve().parent
REF = ROOT / 'docs/reference'
BASE = 'd2d188a'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def baseline(path): return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)
def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links, self.assets, self.values = [], [], [], {}

    def handle_starttag(self, tag, pairs):
        attrs = dict(pairs)
        if 'id' in attrs: self.ids.append(attrs['id'])
        if 'href' in attrs: self.links.append(attrs['href'])
        if 'src' in attrs: self.assets.append(attrs['src'])
        if 'data-long-stride-value' in attrs:
            key, amount = attrs['data-long-stride-value'], float(attrs['data-value'])
            if key in self.values: assert self.values[key] == amount
            self.values[key] = amount


def main():
    merge = module('merge_v098', QA / 'merge-fragment.py')
    builder = module('builder_v098', ROOT / 'tools/build_reference.py')
    old_raw, raw = baseline('docs/reference/catalog.json').decode(), (REF / 'catalog.json').read_text()
    old, data = json.loads(old_raw), json.loads(raw)
    fragment = json.loads((QA / 'long-stride-fragment.json').read_text())
    assert data == merge.expected_data(old, fragment), 'Only bounded fragment semantics may change'
    assert data['game_version'] == old['game_version'] == '0.87.0' and data['save_version'] == 53
    assert len(data['supports']) == len(old['supports']) + 1 == 24
    old_tokens, current_tokens = merge.tokens(old_raw), merge.tokens(raw)
    changed_sections = {key for key in old_tokens if old_tokens[key] != current_tokens[key]}
    assert changed_sections == {'save_version', 'supports', 'support_program_examples', 'skills'}
    assert set(current_tokens) - set(old_tokens) == {'long_stride'}
    retained = [key for key, token in old_tokens.items() if current_tokens[key] == token]
    assert len(retained) == len(old_tokens) - 4
    for section in ['supports', 'support_program_examples', 'skills']:
        a, b = merge.tokens(old_tokens[section]), merge.tokens(current_tokens[section])
        for key, token in a.items():
            if section == 'skills' and key == 'dash':
                x, y = merge.tokens(token), merge.tokens(b[key])
                assert all(y[field] == value for field, value in x.items() if field != 'compatible_supports')
                assert json.loads(y['compatible_supports']) == json.loads(x['compatible_supports']) + ['long_stride']
            else: assert b[key] == token, (section, key)
    html, old_html = (REF / 'index.html').read_text(), baseline('docs/reference/index.html').decode()
    def cards(text):
        return {key: body for body, key in re.findall(r'(<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>)', text, re.S)}
    previous, current = cards(old_html), cards(html)
    new = {'supports-long_stride', 'rules-long_stride'}
    assert set(current) - set(previous) == new and set(previous) <= set(current)
    schema = {'rules-source_tree', 'rules-source_monster_movement', 'rules-source_monster_damage_life', 'rules-source_monster_shield_recharge', 'rules-frost_lock', 'rules-elemental_conversion', 'rules-physical_fire_conversion', 'rules-equipment', 'rules-exploration_maps'}
    intended = schema | {'skills-dash', 'rules-ember_proliferation'}
    changed = {key for key in previous if previous[key] != current[key]}
    assert changed == intended, (changed - intended, intended - changed)
    for key in schema:
        expected = previous[key].replace('当前存档52', '当前存档53').replace('当前存档 52', '当前存档 53').replace('当前存档结构 52', '当前存档结构 53').replace('schema52 / source49 / equipment51', 'schema53 / source49 / equipment51')
        assert current[key] == expected, key
    assert current['rules-ember_proliferation'] == previous['rules-ember_proliferation'].replace('<dt>当前辅助数量</dt><dd>23</dd>', '<dt>当前辅助数量</dt><dd>24</dd>')
    preserved = {key: sha(body.encode()) for key, body in previous.items() if key not in changed}
    for key in data['exploration_maps']['maps']: assert current['maps-' + key] == previous['maps-' + key]
    for key in ['rules-jewel_crafting', 'rules-chaos_defense', 'rules-encircling_cleave']: assert current[key] == previous[key]
    for key in data['monsters']: assert current['monsters-' + key] == previous['monsters-' + key]
    page = Page(); page.feed(html)
    assert len(page.ids) == len(set(page.ids))
    for link in page.links:
        if link.startswith('#'): assert link[1:] in page.ids, link
        elif not re.match(r'^[a-z]+:', link): assert (REF / link.split('#')[0]).resolve().exists(), link
    for path in page.assets:
        if not re.match(r'^[a-z]+:', path): assert (REF / path).is_file(), path
    payload = json.loads(re.search(r'<script id="reference-data" type="application/json">(.*?)</script>', html, re.S)[1])
    records = {row['id']: row for row in payload['records']}
    assert len(records) == len(current)
    for key in new:
        for term in ['长跃', '冲刺', '175', '280', '0.6', '1.2', '保护', '背包']:
            assert term.casefold() in records[key]['search'], (key, term)
    assert '长跃' in records['skills-dash']['search']
    assert '#supports-long_stride' in current['skills-dash'] and '#rules-long_stride' in current['skills-dash']
    rule_html = current['rules-long_stride']
    for term in ['请求距离', '已有保护', '不能穿墙', '沿墙滑动', '不赠宝石', 'schema52', 'LONG_STRIDE.zh-CN.md', 'owned-fixture-after-runtime.json', 'reuse-fixture.json', 'main3-result.json', 'main3.log']:
        assert term in rule_html, term
    expected_values = {'save-version':53, 'source-policy':49, 'equipment-vocabulary':51, 'base-distance':175, 'requested-distance':280, 'base-immunity-grant':.6, 'immunity-grant':0, 'mana-multiplier':1.2, 'compatible-count':3, 'maximum-supports':5, 'merchant-cost':4, 'before-requested_distance':175, 'after-requested_distance':280, 'before-immunity_grant':.6, 'after-immunity_grant':0, 'before-mana':12, 'after-mana':14.4, 'before-cooldown':3, 'after-cooldown':3, 'main-checks':265, 'compiler-checks':138}
    assert page.values.keys() == expected_values.keys()
    for key, amount in expected_values.items(): assert math.isclose(page.values[key], amount, rel_tol=0, abs_tol=1e-10), (key, page.values[key], amount)
    inputs = json.loads((QA / 'export-input-sha256.json').read_text())
    for path, digest in inputs.items(): assert sha((ROOT / path).read_bytes()) == digest, path
    rule = data['long_stride']
    for key in ['actual_main_fixture', 'actual_main_report', 'actual_main_log', 'reuse_fixture', 'runtime_tested_inputs']:
        evidence = rule[key]; assert sha((ROOT / evidence['path']).read_bytes()) == evidence['sha256']
    accepted = json.loads((ROOT / rule['actual_main_report']['path']).read_text())
    fixture = json.loads((ROOT / rule['actual_main_fixture']['path']).read_text())
    reuse = json.loads((ROOT / rule['reuse_fixture']['path']).read_text())
    assert accepted['checks'] == 265 and accepted['failures'] == 0 and not accepted['failures_detail']
    assert fixture['version'] == 53 and rule['group_id'] == reuse['group_id'] == 'group_000008'
    assert rule['active_uid'] == reuse['active_uid'] == 'item_000010'
    assert rule['support_uids'] == reuse['support_uids']
    assert rule['final_support_locations'] == reuse['final_support_locations']
    for uid, location in rule['final_support_locations'].items(): assert fixture['locations'][uid] == location and location['kind'] == 'bag'
    assert rule['skills'] == ['dash'] and rule['compatible_supports'] == ['efficiency', 'quickcast', 'long_stride']
    assert rule['policy'] == {'enabled':True, 'requested_distance':280, 'base_distance':175, 'immunity_grant':0, 'base_immunity_grant':.6, 'mana_multiplier':1.2}
    assert rule['normal_reward_pool_includes_support'] is False and rule['test_offer']['available']
    assert rule['examples']['before']['long_stride_profile'] == {} and rule['examples']['after']['long_stride_profile'] == rule['policy']
    for example in rule['examples'].values(): assert example['initial_count'] == 0 and example['recipe'] == {}
    tracked = subprocess.check_output(['git','ls-tree','-r','--name-only',BASE], cwd=ROOT, text=True).splitlines()
    protected = [p for p in tracked if p.lower().endswith(('.png','.ttf','.otf','.woff','.woff2')) or (p.startswith('docs/reference/') and p not in ['docs/reference/catalog.json','docs/reference/index.html'])]
    font_exception = 'assets/fonts/arena_sans.otf'
    protected_hashes = {}
    for path in protected:
        raw_file = (ROOT / path).read_bytes()
        if path == font_exception: continue
        assert raw_file == baseline(path), path
        protected_hashes[path] = sha(raw_file)
    font_change = {'path':font_exception, 'before_sha256':sha(baseline(font_exception)), 'after_sha256':sha((ROOT / font_exception).read_bytes()), 'scope':'Coordinator updated the runtime subset from the same font with 截/跃; reference uses system fonts and has no local font copy.'}
    assert font_change['before_sha256'] != font_change['after_sha256']
    assert not any(p.startswith('docs/reference/') and p.lower().endswith(('.ttf','.otf','.woff','.woff2')) for p in tracked)
    png = (REF / rule['icon_file']).read_bytes()
    assert png == (ROOT / rule['icon_source'].removeprefix('res://')).read_bytes()
    assert sha(png) == rule['icon_sha256'] == '13540b90703ae35a1c222229c12f27907c224663c94637f82a55ea708c2bc8e7'
    assert png[:8] == b'\x89PNG\r\n\x1a\n' and png[25] == 6
    art = json.loads((REF / 'art/manifest.json').read_text())
    assert builder.build(old, art) == old_html, 'Baseline rendering must remain byte-identical'
    assert builder.build(data, art) == html, 'Current HTML must be deterministic'
    run = json.loads((QA / 'export-run.json').read_text())
    assert run['exit_code'] == 0 and run['export_count'] == 1 and run['input_fingerprints_unchanged']
    assert 'ERROR' not in (QA / 'export.stdout.log').read_text() + (QA / 'export.stderr.log').read_text()
    assert json.loads((QA / 'first-long-stride-fragment.json').read_text()) == {}
    assert 'SCRIPT ERROR: Assertion failed.' in (QA / 'first-export.stderr.log').read_text()
    proof = {'baseline_commit':BASE, 'preserved_raw_top_level_count':len(retained), 'preserved_raw_top_level':retained, 'old_card_count':len(previous), 'current_card_count':len(current), 'unchanged_card_count':len(preserved), 'changed_card_count':len(changed), 'changed_cards':sorted(changed), 'new_cards':sorted(new), 'schema_number_only_cards':sorted(schema), 'current_support_count_only_card':'rules-ember_proliferation', 'old_monsters_maps_chaos_jewels_encircling_byte_identical':True, 'all_local_links_and_chinese_search_pass':True, 'unique_anchor_count':len(page.ids), 'numeric_values_verified':len(expected_values), 'protected_file_count':len(protected_hashes), 'protected_png_count':sum(p.endswith('.png') for p in protected_hashes), 'protected_sha256':protected_hashes, 'runtime_font_change':font_change, 'reference_local_font_count':0, 'new_icon_sha256':sha(png), 'new_icon_dimensions':list(struct.unpack('>II',png[16:24])), 'new_icon_rgba':True, 'input_count':len(inputs), 'input_fingerprints_match':True, 'actual_main_checks':265, 'actual_main_failures':0, 'compiler_checks_reused':138, 'owned_supports_remain_in_bag':True, 'deterministic_current_and_backward_builder':True, 'godot_attempts':2, 'successful_bounded_exports':1, 'initial_failed_attempt_preserved':True, 'scope':'Focused data, provenance, search, links and byte preservation. No Main rerun, old exporter, source coverage, maps, combat matrices, art generation or screenshots.'}
    (QA / 'preservation.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n')
    (QA / 'card-sha256.json').write_text(json.dumps({'baseline_commit':BASE, 'unchanged':preserved, 'changed':{k:{'before':sha(previous[k].encode()), 'after':sha(current[k].encode())} for k in sorted(changed)}, 'new':{k:sha(current[k].encode()) for k in sorted(new)}}, ensure_ascii=False, indent=2) + '\n')
    summary = {k:v for k,v in proof.items() if k not in ['protected_sha256','preserved_raw_top_level']}
    (QA / 'final-result.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()
