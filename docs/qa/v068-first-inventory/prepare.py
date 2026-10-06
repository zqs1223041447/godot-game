from pathlib import Path
import hashlib,json
R=Path('/workspace/scratch/a51485f153de/v067-inward-pull');Q=Path(__file__).resolve().parent
panel=(R/'scripts/ui/canonical_inventory_panel.gd').read_text().replace('CanonicalInventoryPanel','InventoryAuditPanel')
panel += '\nvar audit_times: Dictionary = {}\nvar audit_counts: Dictionary = {}\nfunc audit_mark(label: String, began: int) -> void:\n\taudit_times[label] = int(audit_times.get(label, 0)) + Time.get_ticks_usec() - began\n\taudit_counts[label] = int(audit_counts.get(label, 0)) + 1\n'
for fn in ['_build','refresh','_refresh_crafting','_build_craft_confirmation','_layout_slots']:
 old='func '+fn+'() -> void:';assert panel.count(old)==1;panel=panel.replace(old,'func audit_original'+fn+'() -> void:')
 panel+='\nfunc '+fn+'() -> void:\n\tvar began := Time.get_ticks_usec()\n\taudit_original'+fn+'()\n\taudit_mark("'+fn+'", began)\n'
a='\tvar grid_script: Script = load("res://scripts/ui/unified_bag_grid.gd")';assert panel.count(a)==1
panel=panel.replace(a,'\tvar grid_started := Time.get_ticks_usec()\n'+a+'\n\taudit_mark("grid_script_load", grid_started)\n\tgrid_started = Time.get_ticks_usec()')
a='\tadd_child(_grid)';assert panel.count(a)==1;panel=panel.replace(a,a+'\n\taudit_mark("grid_new_add_ready", grid_started)')
(Q/'panel.gd').write_text(panel)
hud=(R/'scripts/game_hud.gd').read_text().replace('class_name GameHUD\n','').replace('preload("res://scripts/ui/canonical_inventory_panel.gd")','preload("'+str(Q/'panel.gd')+'")');(Q/'hud.gd').write_text(hud)
main=(R/'scripts/main.gd').read_text().replace('preload("res://scripts/game_hud.gd")','preload("'+str(Q/'hud.gd')+'")');(Q/'main.gd').write_text(main)
s=(R/'tools/diagnostics/inventory_projection_v51.gd').read_text().replace('extends "res://scripts/main.gd"','extends "'+str(Q/'main.gd')+'"').replace('/tmp/godot-m1-v051-','/tmp/godot-m1-v068-')
a='\tfunc add_normal_root_xp(amount: int) -> bool:'
methods='''\tfunc item_definition(uid: String) -> Dictionary:
		var began := Time.get_ticks_usec(); var value := super.item_definition(uid)
		mark("item_definition", began); return value
	func snapshot() -> Dictionary:
		var began := Time.get_ticks_usec(); var value := super.snapshot()
		mark("snapshot", began); return value
'''
assert s.count(a)==1;s=s.replace(a,methods+a)
a='\tvar panel = arena.hud._inventory_panel\n\tassert(panel.is_visible_in_tree() and arena.hud.is_blocking())';assert s.count(a)==1
s=s.replace(a,'\tvar panel = arena.hud._inventory_panel\n\trows.back()["panel_nested_nonadditive_us"] = panel.audit_times.duplicate()\n\trows.back()["panel_calls"] = panel.audit_counts.duplicate()\n\tassert(panel.is_visible_in_tree() and arena.hud.is_blocking())')
a='\tassert(not is_instance_valid(arena.hud._inventory_panel))';s=s.replace(a,a+'\n\tvar grid_cached_before := ResourceLoader.has_cached("res://scripts/ui/unified_bag_grid.gd")')
a='\t\t"scope":"One starter-size current-schema fixture;';s=s.replace(a,'\t\t"grid_cached_before_first_I":grid_cached_before,\n\t\t"scope":"One current production-copied main/HUD/panel diagnostic; only timing and dependency redirection added, no UI behavior changes. One starter-size current-schema fixture;')
(Q/'probe.gd').write_text(s)
inputs={str(p.relative_to(R)):{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in (R/'scripts').rglob('*.gd')};(Q/'production-inputs.json').write_text(json.dumps(inputs,indent=2)+'\n');print('Diagnostic-only copied chain prepared, production unchanged')
