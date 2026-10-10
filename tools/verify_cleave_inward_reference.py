"""Bounded cleave/inward content and existing F8 projection verification."""
import hashlib, json, re, subprocess
from pathlib import Path
from fontTools.ttLib import TTFont
from check_font_coverage import string_literals

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/cleave-inward'
BASE = '2c23c4e7cc0cc164b8d3f33d74e46c079075a1f0'
def original(path): return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)

text = (ROOT/'docs/reference/catalog.json').read_text()
new = json.loads(text)
fragment = json.loads((QA/'reference-fragment.json').read_text())
expected = json.loads(original('docs/reference/catalog.json'))
expected['supports']['inward_pull'] = fragment['support']
expected['canonical']['gem_definitions']['support:inward_pull'] = fragment['gem']
expected['skills']['cleave']['compatible_supports'] = fragment['compatible']
expected['support_program_examples']['inward_pull']['examples']['cleave'] = fragment['program_example']
for config, rows in fragment['examples'].items():
    expected['skills']['cleave']['examples'][config] += rows
for field in ['skills','direction','movement','snapshot','scope','damage_scope','risk','migration','source_policy','equipment_vocabulary','test_offer']:
    expected['inward_pull'][field] = fragment['inward_pull'][field]
expected['inward_pull']['examples']['cleave'] = fragment['inward_pull']['examples']['cleave']
assert new == expected, 'Only designated fields may change; all old examples remain exact'
subprocess.run(['python3','tools/merge_tornado_swift_reference.py','--skill','cleave','--support','inward_pull','--qa',str(QA)],cwd=ROOT,check=True)
assert (ROOT/'docs/reference/catalog.json').read_text() == text
html = (ROOT/'docs/reference/index.html').read_text()
pattern = r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
before = {m[1]:m[0] for m in re.finditer(pattern,original('docs/reference/index.html').decode(),re.S)}
after = {m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
assert before.keys() == after.keys()
changed = {key for key in before if before[key] != after[key]}
assert changed == {'skills-cleave','skills-meteor','skills-nova','supports-inward_pull','rules-inward_pull'},changed
for key in ['skills-meteor','skills-nova']:
    assert before[key].replace('牵引辅助：朝真实爆发圆心反转冲量','牵引辅助：朝技能中心施加冲量').replace('查看牵引与伏击冻结快照的代表编译示例','查看牵引与冻结快照的代表编译示例') == after[key]
assert '裂刃成功命中后' in after['skills-cleave'] and '裂刃未命中不牵引' in after['supports-inward_pull']
ids = set(re.findall(r'\bid="([^"]+)"',html))
links = re.findall(r'href="#([^"]+)"',html)
assert all(link in ids for link in links)
coverage = set(TTFont(ROOT/'assets/fonts/arena_sans.otf').getBestCmap())
texts = (ROOT/'scripts/combat/inward_pull_support_rules.gd').read_text() + '\n"牵引配置无效"'
missing = sorted({ch for _,value in string_literals(texts) for ch in value if ord(ch)>127 and not ch.isspace() and ord(ch) not in coverage})
assert not missing,missing
unchanged = ['scripts/combat/delivery_support_rules.gd','scripts/combat/skill_compiler.gd',
             'scripts/combat/projectile_runtime.gd','scripts/combat/damage_resolver.gd',
             'scripts/combat/support_program.gd','scripts/canonical_game_state.gd','scripts/save/canonical_build_rules.gd']
for path in unchanged: assert (ROOT/path).read_bytes() == original(path),path
report = {'baseline':BASE,'changed_f8_cards':sorted(changed),'other_cards_byte_identical':len(before)-len(changed),
          'old_spell_cards_only_link_labels_changed':True,'all_old_catalog_examples_exact':True,
          'new_skill_examples':sum(len(rows) for rows in fragment['examples'].values()),
          'new_rule_pairs':len(fragment['inward_pull']['examples']['cleave']),
          'checked_internal_links':len(links),'font_gaps':missing,'merge_idempotent':True,
          'unchanged_production_paths':unchanged,'catalog_sha256':hashlib.sha256(text.encode()).hexdigest(),
          'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
(QA/'reference-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
