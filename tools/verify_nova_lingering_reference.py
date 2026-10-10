"""Verify bounded nova duration references and unchanged old results."""
import hashlib,json,re,subprocess
from pathlib import Path
from fontTools.ttLib import TTFont
from check_font_coverage import string_literals
ROOT=Path(__file__).resolve().parents[1]
QA=ROOT/'docs/qa/nova-lingering'
BASE='18303a9b8012c28989b785c1809a03f4972641e4'
def original(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
text=(ROOT/'docs/reference/catalog.json').read_text();new=json.loads(text)
f=json.loads((QA/'reference-fragment.json').read_text());expected=json.loads(original('docs/reference/catalog.json'))
expected['supports']['lingering_chill']=f['support']
expected['canonical']['gem_definitions']['support:lingering_chill']=f['gem']
expected['skills']['nova']['compatible_supports']=f['compatible']
expected['support_program_examples']['lingering_chill']['examples']['nova']=f['program_example']
for config,rows in f['examples'].items():expected['skills']['nova']['examples'][config]+=rows
for skill in ['nova','frost']:expected['skills'][skill]['capabilities']=f['native_slow'][skill]
expected['skills']['nova']['slow_duration']=f['native_slow']['nova_base']
assert new==expected,'Every old catalog example remains exact; only designated metadata and new examples'
subprocess.run(['python3','tools/merge_tornado_swift_reference.py','--skill','nova','--support','lingering_chill','--qa',str(QA)],cwd=ROOT,check=True)
assert (ROOT/'docs/reference/catalog.json').read_text()==text
html=(ROOT/'docs/reference/index.html').read_text();pattern=r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
before={m[1]:m[0] for m in re.finditer(pattern,original('docs/reference/index.html').decode(),re.S)}
after={m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
assert before.keys()==after.keys()
changed={key for key in before if before[key]!=after[key]}
assert changed=={'skills-nova','supports-lingering_chill','rules-cold_ailment_duration'},changed
assert '普通减速秒' in after['skills-nova'] and '新星不受冰霜异常时长源属性加成' in after['supports-lingering_chill']
ids=set(re.findall(r'\bid="([^"]+)"',html));links=re.findall(r'href="#([^"]+)"',html)
assert all(link in ids for link in links)
coverage=set(TTFont(ROOT/'assets/fonts/arena_sans.otf').getBestCmap())
texts='\n'.join((ROOT/path).read_text() for path in ['scripts/combat/delivery_support_rules.gd','scripts/combat/damage_preview.gd','scripts/combat/skill_compiler.gd'])
missing=sorted({ch for _,v in string_literals(texts) for ch in v if ord(ch)>127 and not ch.isspace() and ord(ch) not in coverage})
assert not missing,missing
allowed={'scripts/game_data.gd','scripts/main.gd','scripts/combat/skill_compiler.gd','scripts/combat/delivery_support_rules.gd','scripts/combat/damage_preview.gd','scripts/combat/player_trap_runtime.gd'}
production=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'scripts','assets','data','scenes','project.godot'],cwd=ROOT,text=True).splitlines()
for path in production:
    if path not in allowed:assert (ROOT/path).read_bytes()==original(path),path
for method in ['_aim_direction','_nearest_enemy','_chain_damage','_update_traps','_check_map_complete']:
    pattern=r'^func '+method+r'\(.*?(?=^func |\Z)'
    assert re.search(pattern,(ROOT/'scripts/main.gd').read_text(),re.S|re.M)[0]==re.search(pattern,original('scripts/main.gd').decode(),re.S|re.M)[0],method
report={'baseline':BASE,'changed_f8_cards':sorted(changed),'other_cards_byte_identical':len(before)-len(changed),'all_old_catalog_examples_exact':True,'new_nova_examples':sum(map(len,f['examples'].values())),'new_support_rule_pairs':1,'internal_links':len(links),'font_gaps':missing,'merge_idempotent':True,'other_production_asset_files_exact':len(production)-len(allowed),'chain_trigger_completion_and_aim_functions_exact':True,'catalog_sha256':hashlib.sha256(text.encode()).hexdigest(),'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
(QA/'reference-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
