"""Bounded frost-pull reference additions and old-content preservation."""
import hashlib,json,re,subprocess
from pathlib import Path
from fontTools.ttLib import TTFont
from check_font_coverage import string_literals
ROOT=Path(__file__).resolve().parents[1];QA=ROOT/'docs/qa/frost-inward'
BASE='e7e578ee035459f603968cf6fbff0cb10fbbd2d0'
def original(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
text=(ROOT/'docs/reference/catalog.json').read_text();new=json.loads(text)
f=json.loads((QA/'reference-fragment.json').read_text());expected=json.loads(original('docs/reference/catalog.json'))
expected['supports']['inward_pull']=f['support'];expected['canonical']['gem_definitions']['support:inward_pull']=f['gem']
expected['skills']['frost']['compatible_supports']=f['compatible']
expected['support_program_examples']['inward_pull']['examples']['frost']=f['program_example']
for config,rows in f['examples'].items():expected['skills']['frost']['examples'][config]+=rows
for field in ['skills','direction','movement','snapshot','scope','damage_scope','risk','statuses','migration','source_policy','equipment_vocabulary','test_offer']:
 expected['inward_pull'][field]=f['inward_pull'][field]
for skill in ['nova','meteor','cleave']:assert expected['inward_pull']['examples'][skill]==f['inward_pull']['examples'][skill]
expected['inward_pull']['examples']['frost']=f['inward_pull']['examples']['frost']
assert new==expected,'Only designated additions; every old catalog example stays exact'
subprocess.run(['python3','tools/merge_tornado_swift_reference.py','--skill','frost','--support','inward_pull','--qa',str(QA)],cwd=ROOT,check=True)
assert (ROOT/'docs/reference/catalog.json').read_text()==text
html=(ROOT/'docs/reference/index.html').read_text();pattern=r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
before={m[1]:m[0] for m in re.finditer(pattern,original('docs/reference/index.html').decode(),re.S)}
after={m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
assert before.keys()==after.keys()
changed={key for key in before if before[key]!=after[key]}
assert changed=={'skills-frost','supports-inward_pull','rules-inward_pull'},changed
assert '穿透次数' in after['rules-inward_pull'] and '发射时角色位置' in after['skills-frost']
ids=set(re.findall(r'\bid="([^"]+)"',html));links=re.findall(r'href="#([^"]+)"',html)
assert all(link in ids for link in links)
coverage=set(TTFont(ROOT/'assets/fonts/arena_sans.otf').getBestCmap())
texts='\n'.join((ROOT/path).read_text() for path in ['scripts/combat/inward_pull_support_rules.gd','scripts/combat/damage_preview.gd'])
missing=sorted({ch for _,v in string_literals(texts) for ch in v if ord(ch)>127 and not ch.isspace() and ord(ch) not in coverage})
assert not missing,missing
allowed={'scripts/main.gd','scripts/combat/inward_pull_support_rules.gd','scripts/combat/projectile_runtime.gd','scripts/combat/damage_preview.gd'}
production=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'scripts','assets','data','scenes','project.godot'],cwd=ROOT,text=True).splitlines()
for path in production:
 if path not in allowed:assert (ROOT/path).read_bytes()==original(path),path
for method in ['_aim_direction','_nearest_enemy','_chain_damage','_area_damage','_update_traps','_check_map_complete','restart_run']:
 expression=r'^func '+method+r'\(.*?(?=^func |\Z)'
 assert re.search(expression,(ROOT/'scripts/main.gd').read_text(),re.S|re.M)[0]==re.search(expression,original('scripts/main.gd').decode(),re.S|re.M)[0],method
report={'baseline':BASE,'changed_f8_cards':sorted(changed),'other_cards_byte_identical':len(before)-len(changed),'all_old_catalog_examples_exact':True,'new_frost_examples':sum(map(len,f['examples'].values())),'new_pull_rule_pairs':len(f['inward_pull']['examples']['frost']),'internal_links':len(links),'font_gaps':missing,'merge_idempotent':True,'other_production_asset_files_exact':len(production)-len(allowed),'compiler_schema_damage_and_other_delivery_paths_exact':True,'catalog_sha256':hashlib.sha256(text.encode()).hexdigest(),'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
(QA/'reference-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
