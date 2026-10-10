"""Bounded chain/ambush F8 projection and preservation checks."""
import hashlib, json, re, subprocess
from pathlib import Path
from fontTools.ttLib import TTFont
from check_font_coverage import string_literals

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/chain-ambush'
BASE = '95a6460296d416d552ed0079da8b1d0cfbb93edd'
def original(path): return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
text = (ROOT/'docs/reference/catalog.json').read_text()
new = json.loads(text)
fragment = json.loads((QA/'reference-fragment.json').read_text())
expected = json.loads(original('docs/reference/catalog.json'))
expected['supports']['ambush'] = fragment['support']
expected['canonical']['gem_definitions']['support:ambush'] = fragment['gem']
expected['skills']['chain']['compatible_supports'] = fragment['compatible']
expected['support_program_examples']['ambush']['examples']['chain'] = fragment['program_example']
for config, rows in fragment['examples'].items():
    expected['skills']['chain']['examples'][config] += rows
for field in ['skills','snapshot','geometry','statuses','damage_scope','provenance','migration','source_policy','equipment_vocabulary','test_offer']:
    expected['ambush'][field] = fragment['ambush'][field]
expected['ambush']['examples']['chain'] = fragment['ambush']['examples']['chain']
assert new == expected, 'Only designated additions; every old catalog example remains exact'
subprocess.run(['python3','tools/merge_tornado_swift_reference.py','--skill','chain','--support','ambush','--qa',str(QA)],cwd=ROOT,check=True)
assert (ROOT/'docs/reference/catalog.json').read_text() == text
html = (ROOT/'docs/reference/index.html').read_text()
pattern = r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
before = {m[1]:m[0] for m in re.finditer(pattern,original('docs/reference/index.html').decode(),re.S)}
after = {m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
assert before.keys() == after.keys()
changed = {key for key in before if before[key] != after[key]}
assert changed == {'skills-chain','supports-ambush','rules-ambush'},changed
assert '后续寻敌距离' in after['rules-ambush'] and '各跳防御前伤害' in after['rules-ambush']
ids = set(re.findall(r'\bid="([^"]+)"',html))
links = re.findall(r'href="#([^"]+)"',html)
assert all(link in ids for link in links)
coverage = set(TTFont(ROOT/'assets/fonts/arena_sans.otf').getBestCmap())
texts = (ROOT/'scripts/combat/ambush_support_rules.gd').read_text()
missing = sorted({ch for _,value in string_literals(texts) for ch in value if ord(ch)>127 and not ch.isspace() and ord(ch) not in coverage})
assert not missing,missing
unchanged = ['scripts/combat/delivery_support_rules.gd','scripts/combat/skill_compiler.gd',
             'scripts/combat/projectile_runtime.gd','scripts/combat/damage_resolver.gd',
             'scripts/combat/support_program.gd','scripts/canonical_game_state.gd','scripts/save/canonical_build_rules.gd']
for path in unchanged: assert (ROOT/path).read_bytes() == original(path),path
# All other tracked production/data/assets retain their exact baseline bytes.
allowed={'scripts/combat/ambush_support_rules.gd','scripts/combat/player_trap_runtime.gd','scripts/main.gd'}
production=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'scripts','assets','data','scenes','project.godot'],cwd=ROOT,text=True).splitlines()
for path in production:
    if path not in allowed: assert (ROOT/path).read_bytes()==original(path),path
for method in ['_aim_direction','_nearest_enemy']:
    expression=r'^func '+method+r'\(.*?(?=^func |\Z)'
    assert re.search(expression,(ROOT/'scripts/main.gd').read_text(),re.S|re.M)[0]==re.search(expression,original('scripts/main.gd').decode(),re.S|re.M)[0]
report = {'baseline':BASE,'changed_f8_cards':sorted(changed),'other_cards_byte_identical':len(before)-len(changed),
          'all_old_catalog_examples_exact':True,'new_skill_examples':sum(len(rows) for rows in fragment['examples'].values()),
          'new_rule_pairs':len(fragment['ambush']['examples']['chain']),
          'checked_internal_links':len(links),'font_gaps':missing,'merge_idempotent':True,
          'unchanged_production_paths':unchanged,'other_production_asset_files_exact':len(production)-len(allowed),
          'aim_and_nearest_enemy_exact':True,'catalog_sha256':hashlib.sha256(text.encode()).hexdigest(),
          'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
(QA/'reference-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
