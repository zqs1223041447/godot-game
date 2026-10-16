from pathlib import Path
import hashlib,json,shutil,subprocess
r=Path('/workspace/scratch/a51485f153de/godot-game'); d=Path('/tmp/burn-advance-budget-20261015'); c=d/'repo'
if not c.exists(): shutil.copytree(r,c,ignore=shutil.ignore_patterns('.git'),dirs_exist_ok=False)
paths=list((r/'scripts').rglob('*.gd'))+[r/'tools/diagnostics/burn_prediction_cache_20261015.gd']
manifest={str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
json.dump({'head':subprocess.check_output(['git','-C',str(r),'rev-parse','HEAD'],text=True).strip(),'files':manifest},open(d/'frozen-manifest.json','w'),indent=2)
assert all(hashlib.sha256((c/p).read_bytes()).hexdigest()==h for p,h in manifest.items())
s=(c/'scripts/main.gd').read_text()
a=s.index('func _advance_proliferating_burns('); b=s.index('\n\nfunc _flush_ember_deaths',a)
f=s[a:b]
f=f.replace('\t_ember_advancing=true','\tvar diag_total_start: int = Time.get_ticks_usec()\n\t_ember_advancing=true',1)
f=f.replace('\t\tvar targets:Dictionary={}', '\t\tvar diag_start: int = Time.get_ticks_usec()\n\t\tvar targets:Dictionary={}',1)
f=f.replace('\t\t# A complete', '\t\tdiag_start = _diag_add("target_map", diag_start)\n\t\t# A complete',1)
f=f.replace('\t\tif not current_ids.is_empty():','\t\tdiag_start = _diag_add("clock_proof", diag_start)\n\t\tif not current_ids.is_empty():',1)
f=f.replace('\t\t\tif living:', '\t\t\tdiag_start = _diag_add("same_time_cleanup", diag_start)\n\t\t\tif living:',1)
f=f.replace('\t\t\t\t_ember_defer_deaths=false\n\t\t\t\t_flush_ember_deaths()', '\t\t\t\t_ember_defer_deaths=false\n\t\t\t\tdiag_start = _diag_add("settlement", diag_start)\n\t\t\t\t_flush_ember_deaths()\n\t\t\t\tdiag_start = _diag_add("death_transfer", diag_start)',1)
f=f.replace('\t\tfor status:Dictionary in burn_runtime.statuses():','\t\tvar diag_statuses: Array[Dictionary] = burn_runtime.statuses()\n\t\tdiag_start = _diag_add("status_snapshot", diag_start)\n\t\tfor status:Dictionary in diag_statuses:',1)
f=f.replace('\t\tif states.is_empty():break','\t\tdiag_start = _diag_add("death_prediction", diag_start)\n\t\tif states.is_empty():break',1)
f=f.replace('\n\t\t_ember_defer_deaths=true','\n\t\tdiag_start = _diag_add("advance_assembly", diag_start)\n\t\t_ember_defer_deaths=true',1)
f=f.replace('\t\t_ember_defer_deaths=false\n\t\t_flush_ember_deaths()', '\t\t_ember_defer_deaths=false\n\t\tdiag_start = _diag_add("settlement", diag_start)\n\t\t_flush_ember_deaths()\n\t\tdiag_start = _diag_add("death_transfer", diag_start)',1)
f=f.replace('\t_ember_advancing=false','\t_ember_advancing=false\n\tdiagnostic["inclusive_us"] += Time.get_ticks_usec() - diag_total_start',1)
# exact substring replacement above must not partially match deeper indentation
assert '\n\t\t\t\tdiag_start = _diag_add("advance_assembly"' not in f
helper='''var diagnostic: Dictionary = {"inclusive_us":0,"bookkeeping_us":0,"phase_us":{},"phase_calls":{}}
func _diag_add(phase: String, started: int) -> int:
	var stopped: int = Time.get_ticks_usec()
	diagnostic.phase_us[phase] = diagnostic.phase_us.get(phase, 0) + stopped - started
	diagnostic.phase_calls[phase] = diagnostic.phase_calls.get(phase, 0) + 1
	var finished: int = Time.get_ticks_usec()
	diagnostic.bookkeeping_us += finished - stopped
	return Time.get_ticks_usec()

'''
s=s[:a]+helper+f+s[b:]
(d/'main.gd').write_text(s)
h=(r/'tools/diagnostics/burn_prediction_cache_20261015.gd').read_text().replace('"base_commit":"4e581e223bf012c04c94ec1f1a558021feeea03a"','"base_commit":"'+subprocess.check_output(['git','-C',str(r),'rev-parse','HEAD'],text=True).strip()+'"')
h=h.replace('if instrumented:extras=arena.cache20261015_counts.duplicate(true)','if instrumented:extras=arena.diagnostic.duplicate(true)')
h=h.replace('\t\t\ttimings.append(total)','\t\t\ttimings.append(total)\n\t\t\tif instrumented: print("ADVANCE_DIAGNOSTIC ", frame, " ", JSON.stringify(arena.diagnostic))')
h=h.replace('\t\tfor frame:int in range(frames):','\t\tif instrumented: arena.diagnostic = {"inclusive_us":0,"bookkeeping_us":0,"phase_us":{},"phase_calls":{}}\n\t\tfor frame:int in range(frames):')
(d/'harness.gd').write_text(h)
json.dump({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in d.glob('*.gd')},open(d/'instrumentation-manifest.json','w'),indent=2)
