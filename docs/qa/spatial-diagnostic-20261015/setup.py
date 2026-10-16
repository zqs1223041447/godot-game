from pathlib import Path
import hashlib,json
r=Path('/workspace/scratch/a51485f153de/godot-game'); d=Path('/tmp/spatial-diagnostic-20261015')
paths=list((r/'scripts').rglob('*.gd'))+[r/'tools/diagnostics/burn_prediction_cache_20261015.gd']
json.dump({str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},open(d/'source-before.json','w'),indent=2)
s=(r/'scripts/combat/spatial_target_index.gd').read_text().replace('class_name SpatialTargetIndex\n','')
s=s.replace('var _cell_size:', '''var diagnostic: Dictionary = {"updates":0,"aliases":0,"same":0,"removed":0,"inserted":0,"overflow_before":0,"overflow_after":0,"overflow_transitions":0,"update_us":0,"diagnostic_us":0}
var _cell_size:''')
a=s.index('\t# One mutated Dictionary'); b=s.index('\n\n\nfunc query_aabb',a)
s=s[:a]+'''\tvar diagnostic_start: int = Time.get_ticks_usec()
\tvar old_memberships: Array = []
\tvar old_overflows: Array = []
\tdiagnostic.updates += 1
\tfor alias_index: int in _aliases[index]:
\t\told_memberships.append(_memberships[alias_index].duplicate())
\t\told_overflows.append(_overflow.has(alias_index))
\tdiagnostic.diagnostic_us += Time.get_ticks_usec() - diagnostic_start
\tvar update_start: int = Time.get_ticks_usec()
\tfor alias_index: int in _aliases[index]:
\t\t_remove(alias_index)
\t\t_insert(alias_index)
\tdiagnostic.update_us += Time.get_ticks_usec() - update_start
\tdiagnostic_start = Time.get_ticks_usec()
\tvar offset: int = 0
\tfor alias_index: int in _aliases[index]:
\t\tvar before: bool = old_overflows[offset]
\t\tvar after: bool = _overflow.has(alias_index)
\t\tdiagnostic.aliases += 1
\t\tdiagnostic.same += int(before == after and old_memberships[offset] == _memberships[alias_index])
\t\tdiagnostic.removed += old_memberships[offset].size()
\t\tdiagnostic.inserted += _memberships[alias_index].size()
\t\tdiagnostic.overflow_before += int(before)
\t\tdiagnostic.overflow_after += int(after)
\t\tdiagnostic.overflow_transitions += int(before != after)
\t\toffset += 1
\tdiagnostic.diagnostic_us += Time.get_ticks_usec() - diagnostic_start'''+s[b:]
(d/'spatial.gd').write_text(s)
s=(r/'scripts/main.gd').read_text().replace('var enemy_spatial = SpatialTargets.new(64.0)','var enemy_spatial = preload("/tmp/spatial-diagnostic-20261015/spatial.gd").new(64.0)\nvar diagnostic_ai_us: int = 0')
s=s.replace('\t_update_enemies(delta)\n','\tvar diagnostic_ai_start: int = Time.get_ticks_usec()\n\t_update_enemies(delta)\n\tdiagnostic_ai_us += Time.get_ticks_usec() - diagnostic_ai_start\n',1)
(d/'main.gd').write_text(s)
s=(r/'tools/diagnostics/burn_prediction_cache_20261015.gd').read_text().replace('if instrumented:extras=arena.cache20261015_counts.duplicate(true)','if instrumented:extras=arena.enemy_spatial.diagnostic.duplicate(true);extras["ai_inclusive_us"]=arena.diagnostic_ai_us')
s=s.replace('\t\t\ttimings.append(total)','\t\t\ttimings.append(total)\n\t\t\tif instrumented: print("SPATIAL_DIAGNOSTIC ", frame, " ", JSON.stringify(arena.enemy_spatial.diagnostic), " ai_inclusive_us=", arena.diagnostic_ai_us)')
(d/'harness.gd').write_text(s)
json.dump({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in d.glob('*.gd')},open(d/'copies-before.json','w'),indent=2)
