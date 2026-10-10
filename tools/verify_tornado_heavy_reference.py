"""Check only this compatibility expansion and its two existing F8 cards."""
import hashlib, json, re, subprocess
from pathlib import Path
from fontTools.ttLib import TTFont
from check_font_coverage import string_literals

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / 'docs/qa/tornado-heavy'
BASE = 'af02c5ed9b934c4b1cafbe3da12c4b16314bbfea'
def original(path): return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)

old = json.loads(original('docs/reference/catalog.json'))
text = (ROOT/'docs/reference/catalog.json').read_text()
new = json.loads(text)
fragment = json.loads((QA/'reference-fragment.json').read_text())
expected = json.loads(original('docs/reference/catalog.json'))
expected['supports']['heavy_projectiles'] = fragment['support']
expected['canonical']['gem_definitions']['support:heavy_projectiles'] = fragment['gem']
expected['skills']['tornado']['compatible_supports'] = fragment['compatible']
expected['support_program_examples']['heavy_projectiles']['examples']['tornado'] = fragment['program_example']
for config, rows in fragment['examples'].items():
    expected['skills']['tornado']['examples'][config] += rows
assert new == expected
subprocess.run(['python3','tools/merge_tornado_swift_reference.py','--support','heavy_projectiles','--qa',str(QA)],cwd=ROOT,check=True)
assert (ROOT/'docs/reference/catalog.json').read_text() == text

html = (ROOT/'docs/reference/index.html').read_text()
old_html = original('docs/reference/index.html').decode()
pattern = r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
before = {m[1]:m[0] for m in re.finditer(pattern,old_html,re.S)}
after = {m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
assert before.keys() == after.keys()
changed = {key for key in before if before[key] != after[key]}
assert changed == {'skills-tornado','supports-heavy_projectiles'},changed
assert '龙卷母箭与子箭均生效' in after['supports-heavy_projectiles']
for number in ['315.00','195.00']:
    assert number in after['supports-heavy_projectiles']
ids = set(re.findall(r'\bid="([^"]+)"',html))
links = re.findall(r'href="#([^"]+)"',html)
assert all(link in ids for link in links)
font = TTFont(ROOT/'assets/fonts/arena_sans.otf')
coverage = set(font.getBestCmap())
runtime = (ROOT/'scripts/combat/delivery_support_rules.gd').read_text()
missing = sorted({ch for _,value in string_literals(runtime) for ch in value if ord(ch)>127 and not ch.isspace() and ord(ch) not in coverage})
assert not missing,missing
unchanged = ['scripts/combat/skill_compiler.gd','scripts/combat/projectile_runtime.gd','scripts/combat/damage_resolver.gd',
             'scripts/combat/support_program.gd','scripts/main.gd','scripts/canonical_game_state.gd','scripts/save/canonical_build_rules.gd']
for path in unchanged: assert (ROOT/path).read_bytes() == original(path),path
report = {'baseline':BASE,'changed_f8_cards':sorted(changed),'other_cards_byte_identical':len(before)-len(changed),
          'new_examples':sum(len(rows) for rows in fragment['examples'].values()),'checked_internal_links':len(links),
          'font_gaps':missing,'merge_idempotent':True,'unchanged_production_paths':unchanged,
          'catalog_sha256':hashlib.sha256(text.encode()).hexdigest(),'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
(QA/'reference-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
