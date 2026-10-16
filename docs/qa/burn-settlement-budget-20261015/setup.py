from pathlib import Path
import json,hashlib,shutil
old=Path('/tmp/burn-advance-budget-20261015');d=Path('/tmp/burn-settlement-budget-20261015');r=Path('/workspace/scratch/a51485f153de/godot-game')
m=json.loads((old/'frozen-manifest.json').read_text())
assert all(hashlib.sha256((r/p).read_bytes()).hexdigest()==h for p,h in m['files'].items())
shutil.copytree(old/'repo',d/'repo')
shutil.copyfile(old/'frozen-manifest.json',d/'frozen-manifest.json')
s=(d/'repo/scripts/main.gd').read_text();a=s.index('func _settle_burn_segments(');b=s.index('\n\nfunc _record_damage_feedback',a);f=s[a:b]
f=f.replace('\n\tfor segment:', '\n\tvar diag_total_start: int = Time.get_ticks_usec()\n\tfor segment:',1)
f=f.replace('\n\t\tvar raw:', '\n\t\tvar diag_start: int = Time.get_ticks_usec()\n\t\tvar raw:',1)
f=f.replace('\n\t\tif segment.target_kind', '\n\t\tdiag_start = _diag_add("segment_setup", diag_start)\n\t\tif segment.target_kind',1)
f=f.replace('if not alive:continue','if not alive:\n\t\t\t\tdiag_start = _diag_add("player_prepare", diag_start)\n\t\t\t\tcontinue',1)
f=f.replace('if raw<=0.0:continue','if raw<=0.0:\n\t\t\t\tdiag_start = _diag_add("player_prepare", diag_start)\n\t\t\t\tcontinue',1)
f=f.replace('\n\t\t\tif typeof(maximum_fire_bonus)', '\n\t\t\tdiag_start = _diag_add("player_prepare", diag_start)\n\t\t\tif typeof(maximum_fire_bonus)',1)
f=f.replace('\n\t\t\tif not settlement.ok:continue','\n\t\t\tdiag_start = _diag_add("player_defense", diag_start)\n\t\t\tif not settlement.ok:continue',1)
f=f.replace('\n\t\t\t_record_damage_feedback("player"','\n\t\t\tdiag_start = _diag_add("player_resources", diag_start)\n\t\t\t_record_damage_feedback("player"',1)
f=f.replace('\n\t\t\t_finish_player_death()','\n\t\t\tdiag_start = _diag_add("player_feedback", diag_start)\n\t\t\t_finish_player_death()\n\t\t\tdiag_start = _diag_add("player_death", diag_start)',1)
f=f.replace('burn_runtime.remove("monster",int(segment.target_id));continue','burn_runtime.remove("monster",int(segment.target_id))\n\t\t\t\tdiag_start = _diag_add("monster_target", diag_start)\n\t\t\t\tcontinue',1)
f=f.replace('\n\t\t\tsettlement=Defense.incoming_burn(raw,target','\n\t\t\tdiag_start = _diag_add("monster_target", diag_start)\n\t\t\tsettlement=Defense.incoming_burn(raw,target',1)
# remaining uninstrumented validation belongs to monster defense
needle='\n\t\t\tif not settlement.ok:continue\n\t\t\tif exact_deaths'
f=f.replace(needle,'\n\t\t\tdiag_start = _diag_add("monster_defense", diag_start)\n\t\t\tif not settlement.ok:continue\n\t\t\tif exact_deaths',1)
f=f.replace('\n\t\t\tif _apply_enemy_resources(target,settlement):','\n\t\t\tdiag_start = _diag_add("monster_exact_death", diag_start)\n\t\t\tvar diag_applied: bool = _apply_enemy_resources(target,settlement)\n\t\t\tdiag_start = _diag_add("monster_resources", diag_start)\n\t\t\tif diag_applied:',1)
f=f.replace('\n\t\t\t\t_finish_enemy_death(target,','\n\t\t\t\tdiag_start = _diag_add("monster_feedback", diag_start)\n\t\t\t\t_finish_enemy_death(target,',1)
f=f.replace('\n\t\tif settlement.is_empty()', '\n\t\t\t\tdiag_start = _diag_add("monster_death", diag_start)\n\t\tif settlement.is_empty()',1)
f+='\n\t\tdiag_start = _diag_add("trace", diag_start)\n\tdiagnostic["inclusive_us"] += Time.get_ticks_usec() - diag_total_start\n'
helper=(old/'main.gd').read_text();helper=helper[helper.index('var diagnostic:'):helper.index('func _advance_proliferating_burns(')]
s=s[:a]+helper+f+s[b:];(d/'main.gd').write_text(s)
h=(old/'harness.gd').read_text().replace('ADVANCE_DIAGNOSTIC','SETTLEMENT_DIAGNOSTIC');(d/'harness.gd').write_text(h)
for name in ['run.py','verify.py']:
 text=(old/name).read_text().replace(str(old),str(d)).replace('ADVANCE_DIAGNOSTIC','SETTLEMENT_DIAGNOSTIC');(d/name).write_text(text)
json.dump({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in d.glob('*.gd')},open(d/'instrumentation-manifest.json','w'),indent=2)
