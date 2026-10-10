"""Verify the new actual build section and the two intentionally changed F8 cards."""
import hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
QA=ROOT/'docs/qa/chain-shock-build'
BASE='20af5ba04671075c6c4422983d76b93ce4afe1af'
def original(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
text=(ROOT/'docs/reference/catalog.json').read_text()
fragment=json.loads((QA/'reference-fragment.json').read_text())
expected=json.loads(original('docs/reference/catalog.json'))
expected.update(fragment)
assert json.loads(text)==expected, 'No historical catalog data may change'
subprocess.run(['python3','tools/merge_chain_shock_reference.py'],cwd=ROOT,check=True)
assert (ROOT/'docs/reference/catalog.json').read_text()==text
html=(ROOT/'docs/reference/index.html').read_text()
pattern=r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
before={m[1]:m[0] for m in re.finditer(pattern,original('docs/reference/index.html').decode(),re.S)}
after={m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
assert before.keys()==after.keys()
changed={key for key in before if before[key]!=after[key]}
assert changed=={'skills-chain','skills-cleave'},changed
assert '实测构筑 · 分散敌群感电' in after['skills-chain']
assert '再次命中覆盖原冲量' in after['skills-cleave']
for number in ['30.36','286','25.3','26.4']:assert number in after['skills-chain'],number
ids=set(re.findall(r'\bid="([^"]+)"',html))
links=re.findall(r'href="#([^"]+)"',html)
assert all(link in ids for link in links)
# All compiler, support and geometry implementations are unchanged.
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'scripts/combat','scripts/world'],cwd=ROOT).decode().splitlines()
paths+=['scripts/game_data.gd','scripts/canonical_game_state.gd','scripts/save/canonical_build_rules.gd']
for path in paths:assert (ROOT/path).read_bytes()==original(path),path
source=(ROOT/'scripts/main.gd').read_text()
old=original('scripts/main.gd').decode()
replacement='''var cast_facing: Vector2 = _aim_direction()
	# A coincident nearest body has no aim vector, but still intersects cleave.
	if id == "cleave" and cast_facing.is_zero_approx():
		cast_facing = player_facing if not player_facing.is_zero_approx() else Vector2.RIGHT
	player_facing = cast_facing'''
assert source.replace(replacement,'player_facing = _aim_direction()')==old
acceptance=json.loads((QA/'attempt-01.json').read_text())
assert acceptance['failures']==0 and acceptance['checks']==426
assert hashlib.sha256((QA/'owned.json').read_bytes()).hexdigest()==acceptance['owned_sha256']
report={'baseline':BASE,'changed_f8_cards':sorted(changed),'other_cards_byte_identical':len(before)-len(changed),
        'all_old_catalog_data_exact':True,'checked_internal_links':len(links),'merge_idempotent':True,
        'unchanged_combat_world_and_catalog_files':len(paths),'main_change_only_cleave_zero_aim':True,
        'owned_sha256':acceptance['owned_sha256'],'catalog_sha256':hashlib.sha256(text.encode()).hexdigest(),
        'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
(QA/'reference-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
