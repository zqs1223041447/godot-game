"""Narrow data/code/F8 verification for the shared zero-heading correction."""
import hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
QA=ROOT/'docs/qa/aim-overlap'
BASE='b92c2e7f4dbb99e58ba379d572851e4461de84b1'
def original(path):return subprocess.check_output(['git','show',BASE+':'+path],cwd=ROOT)
assert (ROOT/'docs/reference/catalog.json').read_bytes()==original('docs/reference/catalog.json')
html=(ROOT/'docs/reference/index.html').read_text()
pattern=r'<article\b[^>]*\bid="([^"]+)"[^>]*>.*?</article>'
before={m[1]:m[0] for m in re.finditer(pattern,original('docs/reference/index.html').decode(),re.S)}
after={m[1]:m[0] for m in re.finditer(pattern,html,re.S)}
assert before.keys()==after.keys()
changed={key for key in before if before[key]!=after[key]}
assert changed=={'skills-bolt','skills-frost','skills-shade_bolt','skills-tornado','skills-dash','rules-projectiles'},changed
ids=set(re.findall(r'\bid="([^"]+)"',html))
links=re.findall(r'href="#([^"]+)"',html)
assert all(link in ids for link in links)
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE,'scripts/combat','scripts/world'],cwd=ROOT).decode().splitlines()
paths+=['scripts/game_data.gd','scripts/canonical_game_state.gd','scripts/save/canonical_build_rules.gd']
for path in paths:assert (ROOT/path).read_bytes()==original(path),path
source=(ROOT/'scripts/main.gd').read_text()
old=original('scripts/main.gd').decode()
new_aim='''		var offset: Vector2 = Vector2(nearest.pos) - player_pos
		if not offset.is_zero_approx(): return offset.normalized()
	# A coincident target gives no heading. Keep the existing facing before
	# fan rotation and muzzle offset instead of letting every carrier face right.
	return player_facing if not player_facing.is_zero_approx() else Vector2.RIGHT'''
old_aim='''		return (Vector2(nearest.pos) - player_pos).normalized()
	return player_facing'''
old_local='''	var cast_facing: Vector2 = _aim_direction()
	# A coincident nearest body has no aim vector, but still intersects cleave.
	if id == "cleave" and cast_facing.is_zero_approx():
		cast_facing = player_facing if not player_facing.is_zero_approx() else Vector2.RIGHT
	player_facing = cast_facing'''
assert old.count(old_aim)==1 and old.count(old_local)==1
assert source==old.replace(old_aim,new_aim).replace(old_local,'\tplayer_facing = _aim_direction()')
pre=json.loads((QA/'before.json').read_text())
post=json.loads((QA/'final.json').read_text())
assert pre['checks']==122 and pre['failures']==29 and post['checks']==244 and post['failures']==0
assert pre['regular']==post['regular']
assert len(post['regular'])==5
report={'baseline':BASE,'changed_f8_cards':sorted(changed),'other_cards_byte_identical':len(before)-len(changed),
        'catalog_bytes_unchanged':True,'checked_internal_links':len(links),
        'unchanged_combat_world_and_catalog_files':len(paths),'only_shared_aim_and_removed_local_fallback':True,
        'pre_fix_checks':pre['checks'],'pre_fix_failures':pre['failures'],'final_checks':post['checks'],
        'final_failures':post['failures'],'nonoverlap_actual_samples_exact':len(post['regular']),
        'html_sha256':hashlib.sha256(html.encode()).hexdigest()}
(QA/'reference-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
