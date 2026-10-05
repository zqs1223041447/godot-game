#!/usr/bin/env python3
"""Focused offline Shock catalog, rendered evidence, links, and same-source art checks."""
import hashlib
import json
import math
import re
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / 'docs/reference'


class ShockPage(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.article = None
        self.links = []
        self.images = {}
        self.values = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.add(attrs['id'])
        if tag == 'article':
            self.article = attrs.get('id')
        if self.article in ('supports-shock', 'rules-shock'):
            if tag == 'a':
                self.links.append(attrs.get('href', ''))
            if tag == 'img':
                self.images[self.article] = attrs['src']
        if 'data-shock-value' in attrs:
            assert self.article == 'rules-shock'
            key = attrs['data-shock-value']
            assert key not in self.values, 'Duplicate numeric evidence: ' + key
            self.values[key] = float(attrs['data-value'])

    def handle_endtag(self, tag):
        if tag == 'article':
            self.article = None


def near(actual, expected):
    assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), (actual, expected)


def main():
    data = json.loads((REF / 'catalog.json').read_text())
    source = (REF / 'index.html').read_text()
    page = ShockPage()
    page.feed(source)
    shock = data['shock']
    assert shock['player_policy'] == {'duration': 2, 'hit_damage_taken_increased': .15,
                                      'hit_multiplier': .8, 'mana_multiplier': 1.2}
    assert shock['enemy_policy'] == {'duration': 1, 'hit_damage_taken_increased': .15}
    assert shock['save_version'] == data['save_version'] == 31
    assert data['supports']['shock']['family'] == data['support_program_examples']['shock']['family'] == 'shock'
    skills = {'bolt', 'nova', 'chain'}
    assert set(shock['examples']) == set(data['supports']['shock']['skills']) == skills
    assert set(shock['incompatible_skills']) == set(data['skills']) - skills
    expected = {key: value for key, value in shock['player_policy'].items()}
    for skill, example in shock['examples'].items():
        near(example['supported_hit'], example['before_hit'] * .8)
        near(example['mana'], example['before_mana'] * 1.2)
        assert not example['unsupported_cast_has_policy']
        profile = example['profile']
        assert profile['trigger'] == 'positive_lightning_hit_after_settlement'
        assert profile['affects_hits_only'] and profile['applies_after_current_hit']
        assert not profile['affects_dot'] and profile['stacking'] == 'refresh_equal'
        assert profile['roles'] == {'bolt': ['projectile'], 'nova': ['direct'], 'chain': ['bounce']}[skill]
        for field, value in shock['player_policy'].items():
            near(profile[field], value)
        for field in ['before_hit', 'supported_hit', 'before_mana', 'mana']:
            expected[skill + '-' + field] = example[field]
    for skill, definition in data['skills'].items():
        assert ('shock' in definition['compatible_supports']) == (skill in skills)
    sample = shock['settlement_example']
    assert not sample['first_status']['active'] and sample['later_status']['active']
    near(sample['first_hit']['health_lost'], 100)
    near(sample['later_hit']['health_lost'], 115)
    near(sample['burn_while_shocked']['health_lost'], 100)
    assert sample['refreshed']['refreshed'] and not sample['expired']['active']
    near(sample['refresh_status']['hit_damage_taken_increased'], .15)
    near(sample['refresh_status']['status']['expires_at'], 12.5)
    enemy = shock['enemy_attack']
    attack = data['monster_attacks']['locked_circle_lightning']
    assert shock['enemy_template'] == 'storm_skitter'
    assert enemy == data['monsters']['storm_skitter']['telegraph_policy'] == attack['policy']
    assert enemy['shock_policy'] == shock['enemy_policy']
    assert enemy['profile'] == {'windup_seconds': .7, 'recovery_seconds': 1.6, 'radius': 65, 'damage_multiplier': 1.4}
    assert '不施加冻结或感电' not in attack['description']
    assert shock['merchant_quote']['cost'] == {'calibration_shard': 4}
    assert shock['test_offer']['available'] and shock['test_offer']['price_label'] == '测试免费'
    migration = shock['migration_example']
    assert (migration['from_version'], migration['to_version']) == (30, 31)
    assert migration['changed_fields'] == ['version']
    assert migration['items_before'] == migration['items_after'] and migration['granted_items'] == 0
    assert not shock['normal_reward_pool_includes_support']
    oracle = json.loads((ROOT / 'docs/qa/v052-shock-integration/fixtures/v30-vocabulary-oracle.json').read_text())
    assert data['normal_journey']['gem_vocabulary'] == oracle['gem_definitions']
    assert [entry['ordinal'] for entry in shock['reward_ordinals']] == list(range(1, len(shock['reward_ordinals']) + 1))
    assert [entry['definition_id'] for entry in shock['reward_ordinals']] == oracle['milestones'][:len(shock['reward_ordinals'])]
    expected.update({
        'first_hit': 100, 'later_hit': 115, 'burn_while_shocked': 100,
        'refreshed_at': 10.5, 'expires_at': 12.5, 'enemy_duration': 1,
        'enemy_increased': .15, 'windup_seconds': .7, 'radius': 65,
        'recovery_seconds': 1.6, 'enemy_hit_multiplier': 1.4,
        'merchant_cost': 4, 'save_version': 31, 'granted_items': 0,
    })
    assert set(page.values) == set(expected)
    for key, value in expected.items():
        near(page.values[key], value)
    assert {'rules-shock', 'supports-shock'} <= page.ids
    assert all(url.startswith('#') and url[1:] in page.ids for url in page.links)
    assert page.images['supports-shock'] == shock['icon_file'] == 'originals/shock.png'
    assert shock['icon_source'] == 'res://assets/ui/grimoire/shock.png'
    original = (ROOT / shock['icon_source'].removeprefix('res://')).read_bytes()
    assert (REF / shock['icon_file']).read_bytes() == original
    article = re.search(r'<article\b[^>]*id="rules-shock"[^>]*>.*?</article>', source, re.S).group()
    assert '首跳＋末跳预览合计' in article and '不是单次命中或整次施放总伤害' in article
    for field in ['scope', 'settlement', 'damage_scope', 'stacking', 'lifecycle', 'migration', 'source_words']:
        assert shock[field] in article
    assert '<style>' + (REF / 'reference.css').read_text() + '</style>' in source
    assert '<script>' + (REF / 'reference.js').read_text() + '</script>' in source
    print('Shock reference: policies, 3 compiled skills, post-hit/refresh/DOT evidence, enemy telegraph, schema31, old reward ordinals, links and icon bytes PASS')
    print('Shock icon SHA256: ' + hashlib.sha256(original).hexdigest())


if __name__ == '__main__':
    main()
