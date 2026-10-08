extends "res://tests/attack_elemental_passive_test.gd"
## Existing assertions and Main hit path; only this bounded mechanism runs.
const Will = preload("res://scripts/combat/iron_will_rules.gd")
const Conversion = preload("res://scripts/combat/physical_fire_conversion_rules.gd")
const CAPTURE := "res://docs/qa/iron-will/"
const TARGET := "50288"
const WILL_LINE := "Strength's Damage bonus applies to all Spell Damage as well"
const WILL_ROUTE := ["58833","2151","37690","48423","6204","63976","16775","46910",TARGET]
const SAVE := "user://build_save.json"
var evidence: Array[Dictionary] = []
func check(ok: bool, label: String) -> void:
	evidence.append({"label":label,"ok":ok}); super.check(ok,label)
func captured(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value,"",true,true))
func source_checks() -> void:
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CAPTURE+"schema57-oracle.json"))
	var frozen := {}
	for id: String in Source.Data.nodes():
		if Source.Data.node(id).type == "mastery":
			for effect: Dictionary in Source.Data.node(id).mastery_effects: frozen[id+":"+str(effect.effect)] = Source.node_effect(id,int(effect.effect),57)
		else: frozen[id+":0"] = Source.node_effect(id,0,57)
	check(frozen.size() == oracle.effects_count and JSON.stringify(captured(frozen),"",true,true).sha256_text() == oracle.effects_policy57_sha256,"Entire frozen57 policy exactly matches the pre-edit normalized SHA256")
	check(Source.line_effect(WILL_LINE).grants == [{"stat":"iron_will","value":1.0,"mode":"flat"}],"Only exact pinned wording grants the new rule flag")
	var occurrences: Array[String] = []
	for id: String in Source.Data.nodes():
		if Source.Data.node(id).stats.has(WILL_LINE): occurrences.append(id)
	check(occurrences == [TARGET],"Exact wording occurs only at existing standard keystone50288")
	for version: int in [19,45,55,56,57]:
		check(not Source.line_effect(WILL_LINE,version).supported and Source.node_effect(TARGET,0,version).status == "unsupported","Frozen old policy rejects Iron Will: %d" % version)
		check(Source.node_effect(TARGET,0,58).status == "full","Current/old caches remain independent")
	check(captured(Source.node_effect("12926",0,57)) == oracle.selected_effects["12926"] and captured(Source.node_effect("12926",0,58)) == oracle.selected_effects["12926"],"Iron Grip source effect remains unchanged")
	check(not Patterns.parse_line(WILL_LINE,false).supported,"Disabled earlier vocabulary cannot open the new keystone")
	for line: String in [WILL_LINE+".",WILL_LINE+" while Chilled"," "+WILL_LINE,WILL_LINE+"\n","Strength's Damage bonus applies to Physical Spell Damage as well"]:
		check(not Source.line_effect(line).supported,"Other wording/condition/physical-only variants stay unsupported: "+line)
	check(Locale.node_name(TARGET) == "铁意志" and Locale.line_status(WILL_LINE).implemented and not Locale.display_line(WILL_LINE).contains(Locale.NOT_IMPLEMENTED),"Existing official Chinese name retained; complete wording has actual consumer")
	for anchor: Dictionary in Locale.STAT_CONSUMER_GROUPS.iron_will.code_checks:
		check(FileAccess.get_file_as_string("res://"+anchor.path).contains(anchor.contains),"Consumer evidence points to production code: "+anchor.path)
	for index: int in range(1,WILL_ROUTE.size()):
		check(Source.Data.adjacency(WILL_ROUTE[index-1]).has(WILL_ROUTE[index]),"Real standard edge: %s→%s" % [WILL_ROUTE[index-1],WILL_ROUTE[index]])
func arithmetic_checks() -> void:
	# Explicit numeric context, not a claimed player item: Strength20 + OTHER melee30.
	var stats := {"damage":100.0,"strength":100.0,"iron_will":1.0,"melee_physical_increased":0.5,"spell_increased":0.3,"global_increased":0.1}
	var snapshot: Dictionary = Combat.snapshot(stats,[])
	var base := {"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":100.0}
	var packet := {"base":base,"tags":["hit","spell","projectile"],"skill_id":"shade_bolt"}
	var result: Dictionary = Damage.resolve(packet,snapshot.modifiers)
	for type: String in Damage.TYPES: close(result.components[type],160.0,"ALL spell types get Strength20 + spell30 + global10 once, no other melee30: "+type)
	var more: Array = snapshot.modifiers.duplicate(true)
	more.append({"id":"other-more","mode":"more","value":0.25,"all_tags":["spell"]})
	close(Damage.resolve(packet,more).components.chaos,200.0,"Spell INC sums before independent MORE")
	for tags: Array in [["hit","attack","projectile"],["hit","attack","melee"],["hit","area","secondary","explosion"]]:
		packet.tags = tags
		result = Damage.resolve(packet,snapshot.modifiers)
		close(result.components.physical,160.0 if tags.has("melee") else 110.0,"Attack/independent explosion gains no Iron Will")
		close(result.components.fire,110.0,"Attack/independent explosion fire excludes spell source")
	packet.tags = ["hit","spell","area","explosion"]
	close(Damage.resolve(packet,snapshot.modifiers).components.fire,160.0,"A genuine spell-tagged event qualifies even when called an explosion")
	stats.iron_grip = 1.0
	snapshot = Combat.snapshot(stats,[])
	packet.tags = ["hit","spell","projectile"]
	close(Damage.resolve(packet,snapshot.modifiers).components.physical,160.0,"Both flags: projectile spell gets Will once, never Grip")
	packet.tags = ["hit","attack","projectile"]
	close(Damage.resolve(packet,snapshot.modifiers).components.physical,130.0,"Both flags: projectile attack gets Grip once, never Will")
	close(Damage.resolve(packet,snapshot.modifiers).components.chaos,110.0,"Grip remains physical-only while Will remains spell-only")
	var addition: Dictionary = Combat.snapshot({"damage":100.0,"strength":100.0,"iron_will":1.0,"spell_added_cold":10.0,"spell_added_lightning":20.0},[])
	var added_cast: Dictionary = Compiler.compile_group("frost",addition,[])
	check(added_cast.ok,"Existing actual frost recipe admits typed spell additions")
	var added_damage: Dictionary = Damage.resolve(added_cast.packets.projectile,added_cast.snapshot.modifiers)
	close(added_damage.components.cold,112.2,"Frost intrinsic85 + added8.5 receives20% exactly once")
	close(added_damage.components.lightning,20.4,"Added lightning17 receives20% exactly once")
	# The existing flat spell assembly protocol permits physical numeric sources.
	# This is an explicit arithmetic fixture, not a new live physical affix or skill.
	for conversion: String in ["physical_to_fire_conversion","physical_to_cold_conversion","physical_to_lightning_conversion","all"]:
		var fixture: Dictionary = stats.duplicate(true)
		if conversion == "all":
			for key: String in Conversion.STATS.values(): fixture[key] = 0.4
		else: fixture[conversion] = 0.4
		var cast_source: Dictionary = Combat.snapshot(fixture,[])
		cast_source.added_damage.spell = {"physical":100.0,"fire":50.0}
		var cast: Dictionary = Compiler.compile_group("shade_bolt",cast_source,[])
		check(cast.ok,"Existing chaos-spell recipe compiles numeric physical-added conversion fixture: "+conversion)
		var damage: Dictionary = Damage.resolve(cast.packets.projectile,cast.snapshot.modifiers)
		close(damage.components.chaos,384.0,"Native chaos240 gets one combined60% INC")
		if conversion == "all":
			close(damage.components.get("physical",0.0),0.0,"120% request normalizes; no physical remainder")
			close(damage.components.fire,320.0,"Normalized converted80 and native fire120 each receive60% once")
			close(damage.components.cold,128.0,"Normalized converted cold gets one spell source")
			close(damage.components.lightning,128.0,"Normalized converted lightning gets one spell source")
		else:
			var type := conversion.trim_prefix("physical_to_").trim_suffix("_conversion")
			close(damage.components.physical,230.4,"Remaining physical144 receives spell INC once: "+type)
			close(damage.components[type],153.6+(192.0 if type == "fire" else 0.0),"Converted96 and native same-type part separately receive one source: "+type)
		for detail: Dictionary in damage.details:
			for part: Dictionary in detail.parts:
				check(part.modifiers.count("iron_will_strength_increased") == 1 and not part.modifiers.has("iron_grip_strength_physical_increased"),"Each native/converted portion has one Will and no Grip")
	var source: Dictionary = Rules.decode_v57(JSON.parse_string(FileAccess.get_file_as_string(CAPTURE+"schema57-town.json")))
	var unit_candidate: Dictionary = source.duplicate(true); unit_candidate.version = 58; unit_candidate.talents.allocated.append(TARGET); unit_candidate.talents.normal_points -= 1
	check(Rules.reason(unit_candidate).is_empty(),"Explicit rounded-attribute unit candidate uses the legal eight-point source route")
	for strength: float in [0.0,4.49,4.5,5.0,9.49,9.5,10.0,40.0,50.0]:
		var raw: Dictionary = Game._stats_for(source)
		raw.strength = strength-40.0; raw.melee_physical_increased = 0.3
		var derived: Dictionary = Source.apply_stats(raw,unit_candidate)
		close(derived.strength,roundf(strength),"Final Strength rounding precedes native five-point staircase")
		var fraction: float = floorf(roundf(strength)/5.0)*0.01
		close(derived.melee_physical_increased,0.3+fraction,"Original native melee coefficient preserved with other melee supply")
		close(Combat.snapshot(derived,[]).iron_will.strength_increased,fraction,"Will reuses the exact native final Strength coefficient")
	check(not Combat.snapshot({"strength":100.0},[]).has("iron_will") and not Combat.snapshot({"strength":100.0,"iron_will":0.0},[]).has("iron_will"),"Absent/zero rule is inert and preserves old snapshot shape")
	for flag: Variant in [true,-1.0,0.5,NAN,INF]: check(not Compiler.compile_basic(Combat.snapshot({"strength":100.0,"iron_will":flag},[])).ok,"Malformed source flags are rejected by compiler")
	var invalid: Dictionary = snapshot.duplicate(true); invalid.iron_will.strength_increased = 0.5
	check(not Compiler.compile_group("frost",invalid,[]).ok,"Aggregate melee bucket cannot replace independently derived Strength amount")
func transaction_checks() -> void:
	var file := FileAccess.open(SAVE,FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(CAPTURE+"schema57-town.json")); file.close()
	var game := Game.new()
	check(game.load_build(SAVE) and game.level == 5 and game.talent_points == 2,"Existing earned level5/seven-paid-point57 profile migrates lawfully")
	var before: Dictionary = game.snapshot()
	var baseline: Dictionary = game.get_combat_snapshot()
	var old_stats: Dictionary = game.get_stats()
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CAPTURE+"schema57-oracle.json"))
	check(captured(old_stats) == oracle.stats and captured(baseline) == oracle.snapshot,"Inactive stats/snapshot match original57 production capture")
	for skill: String in oracle.casts:
		var cast: Dictionary = Compiler.compile_basic(baseline) if skill == "basic" else Compiler.compile_group(skill,baseline,[])
		check(cast.ok and captured(cast.snapshot) == oracle.casts[skill].snapshot and captured(Damage.resolve(Combat.event_packet(cast.snapshot,skill,"projectile"),cast.snapshot.modifiers)) == oracle.casts[skill].damage,"Relevant inactive cast matches pre-edit capture: "+skill)
	var panel := PassivePanel.new(); root.add_child(panel); panel.setup(game,SAVE)
	panel._node_clicked(TARGET,MOUSE_BUTTON_LEFT,false); panel._node_hovered(TARGET,Rect2())
	check(not panel._allocate.disabled and panel._detail.text.contains("铁意志") and not panel._detail.text.contains(Locale.NOT_IMPLEMENTED) and panel._tree._nodes[TARGET].status == "implemented","Actual Chinese detail/canvas/button agrees with complete mechanism")
	var disk := FileAccess.get_file_as_bytes(SAVE)
	check(DirAccess.make_dir_absolute(SAVE+".tmp") == OK,"Inject final allocation write fault")
	check(not game.allocate_passive(TARGET,0,game.revision(),SAVE).ok and game.snapshot() == before and game.get_combat_snapshot() == baseline and FileAccess.get_file_as_bytes(SAVE) == disk,"Failed allocation spends no point and publishes no snapshot or disk change")
	check(DirAccess.remove_absolute(SAVE+".tmp") == OK,"Remove only isolated allocation fault")
	var saves: int = game.successful_saves; panel._allocate.pressed.emit()
	check(game.snapshot().talents.allocated == WILL_ROUTE and game.talent_points == 1 and game.successful_saves == saves+1,"Actual button pays eighth route point exactly once")
	var after: Dictionary = game.snapshot(); var current: Dictionary = game.get_combat_snapshot()
	var new_stats: Dictionary = game.get_stats(); new_stats.erase("iron_will")
	check(new_stats == old_stats,"Only Will flag added; native Strength, capacities and melee bonuses stay unchanged")
	for field: String in Rules.FIELDS:
		if field not in ["talents","revision"]: check(after[field] == before[field],"Allocation preserves unrelated canonical field: "+field)
	actual_hit_checks(game,baseline,current)
	var reopened := Game.new()
	check(reopened.load_build(SAVE) and reopened.snapshot() == after and reopened.save_attempts == 0 and reopened.get_combat_snapshot() == current,"Selected58 reopens without rewrite")
	var forged: Dictionary = after.duplicate(true); forged.version = 57
	check(not Rules.reason_v57(forged).is_empty() and Rules.decode_v57(captured(forged)).is_empty(),"Old57 rejects injected new allocation before migration")
	check(not game.refund_passive("46910",game.revision(),SAVE).ok and game.snapshot() == after,"Original bridge refund restriction preserved")
	flight_checks(game,SAVE,current)
	check(game.snapshot().talents == after.talents and game.get_combat_snapshot() == current,"Flight checks restore point balance, original owned equipment and build snapshot")
	after = game.snapshot(); disk = FileAccess.get_file_as_bytes(SAVE)
	check(DirAccess.make_dir_absolute(SAVE+".tmp") == OK,"Inject final refund write fault")
	check(not game.refund_passive(TARGET,game.revision(),SAVE).ok and game.snapshot() == after and FileAccess.get_file_as_bytes(SAVE) == disk,"Failed refund preserves points/rule/disk")
	check(DirAccess.remove_absolute(SAVE+".tmp") == OK,"Remove isolated refund fault")
	check(game.refund_passive(TARGET,game.revision(),SAVE).ok and game.talent_points == 2 and game.get_stats() == old_stats and game.get_combat_snapshot() == baseline,"Successful refund returns one point and exact inactive stats/snapshot")
	panel.queue_free()
func arena_for(game, path: String):
	var arena = load("res://scenes/main.tscn").instantiate(); arena.state = game; arena.build_save_path = path
	root.add_child(arena); arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	arena.enemies.clear(); arena.monster_runtime.reset(); return arena
func actual_hit_checks(game, baseline: Dictionary, current: Dictionary) -> void:
	var arena = arena_for(game,SAVE)
	var enemy: Dictionary = arena._spawn_monster("crawler",Vector2(600,300),"ordinary","normal",[])
	check(not enemy.is_empty(),"Actual Main admitted-hit target exists")
	if enemy.is_empty(): arena.free(); return
	enemy.spawn = 0.0; enemy.shield = 0.0; enemy.armour = 0.0; enemy.resistances = {}
	for skill: String in ["frost","shade_bolt","basic","cleave"]:
		var role := "direct" if skill == "cleave" else "projectile"
		var losses: Array[float] = []; var raw_total := 0.0
		for source: Dictionary in [baseline,current]:
			var cast: Dictionary = Compiler.compile_basic(source) if skill == "basic" else Compiler.compile_group(skill,source,[])
			check(cast.ok,"Actual relevant spell/attack compiles: "+skill)
			var packet: Dictionary = Combat.event_packet(cast.snapshot,skill,role)
			raw_total = 0.0
			for amount: float in packet.base.values(): raw_total += amount
			enemy.health = 100000.0; enemy.max_health = 100000.0; arena.damage_trace.clear()
			arena._apply_damage_packet(enemy,packet,cast.snapshot,Color.WHITE,0.0,{"accuracy_checked":true,"cast_id":58,"phase":role})
			check(arena.damage_trace.size() == 1,"One actual Main admitted-hit settlement: "+skill)
			losses.append(100000.0-float(enemy.health))
		close(losses[1]-losses[0],raw_total*0.08 if skill in ["frost","shade_bolt"] else 0.0,"Real cold/chaos spell health loss adds8%; attacks unchanged: "+skill)
	var old_cast: Dictionary = Compiler.compile_group("frost",baseline,[])
	var new_cast: Dictionary = Compiler.compile_group("frost",current,[])
	check(Damage.resolve(Combat.secondary_packet(old_cast.snapshot,"frost"),old_cast.snapshot.modifiers) == Damage.resolve(Combat.secondary_packet(new_cast.snapshot,"frost"),new_cast.snapshot.modifiers),"Actual spell-carrier independent explosion has no spell eligibility")
	arena.free()
func flight_checks(game, path: String, current: Dictionary) -> void:
	var arena = arena_for(game,path)
	var enemy: Dictionary = arena._spawn_monster("crawler",Vector2(700,300),"ordinary","normal",[])
	check(not enemy.is_empty(),"Actual finite flight target exists")
	if enemy.is_empty(): arena.free(); return
	enemy.spawn = 0.0; enemy.shield = 0.0; enemy.armour = 0.0; enemy.resistances = {}; enemy.health = 100000.0; enemy.max_health = 100000.0
	var cast: Dictionary = Compiler.compile_group("frost",current,[])
	check(arena._shoot(Vector2(600,300),Vector2.RIGHT,cast.packets.projectile,Color.WHITE,0,0,520.0,{"snapshot":cast.snapshot}),"Actual cold-spell carrier launches with Strength40/8%")
	var old_shot: Dictionary = arena.projectiles[0].duplicate(true)
	var strength_node := ""
	for id: String in game.available_passives():
		if Source.Data.node(id).stats == ["+10 to Strength"]: strength_node = id; break
	check(not strength_node.is_empty() and game.allocate_passive(strength_node,0,game.revision(),path).ok,"Last earned point buys legal existing Strength+10 branch: "+strength_node)
	close(game.get_stats().strength,50.0,"Actual paid Strength40→50")
	close(game.get_combat_snapshot().iron_will.strength_increased,0.10,"Future spell snapshot uses10%")
	check(game.move_item("swift_blade",{"kind":"equipment","slot_id":"weapon"},game.revision(),path).ok,"Actual swap uses existing owned blade; no new item")
	check(arena.projectiles[0].snapshot == old_shot.snapshot and arena.projectiles[0].payload == old_shot.payload,"Old flight snapshot/base unchanged after paid Strength and weapon swap")
	var next: Dictionary = Compiler.compile_group("frost",game.get_combat_snapshot(),[])
	check(next.ok and next.packets.projectile.base != old_shot.payload.base,"Next spell captures changed weapon base and Strength source")
	check(arena._shoot(Vector2(600,300),Vector2.RIGHT,next.packets.projectile,Color.WHITE,0,0,520.0,{"snapshot":next.snapshot}),"Next actual spell launches with swapped build")
	var new_shot: Dictionary = arena.projectiles[1].duplicate(true)
	var wanted: float = Damage.resolve(old_shot.payload,old_shot.snapshot.modifiers,{},float(old_shot.snapshot.get("critical_roll",{}).get("multiplier",1.0))).total
	var new_wanted: float = Damage.resolve(new_shot.payload,new_shot.snapshot.modifiers,{},float(new_shot.snapshot.get("critical_roll",{}).get("multiplier",1.0))).total
	arena._update_projectiles(0.25)
	check(arena.damage_trace.size() == 2,"Old/new spells use real flight contacts and settlement")
	close(arena.damage_trace[0].total,wanted,"Old actual hit retains original base and8%")
	close(arena.damage_trace[1].total,new_wanted,"New actual hit uses changed base and10%")
	close(100000.0-float(enemy.health),wanted+new_wanted,"Both real spell contacts produce exact health loss")
	check(game.move_item("ember_wand",{"kind":"equipment","slot_id":"weapon"},game.revision(),path).ok and game.refund_passive(strength_node,game.revision(),path).ok,"Restore original owned weapon and refund only paid Strength branch")
	arena.projectiles.clear(); arena.damage_trace.clear()
	cast = Compiler.compile_group("shade_bolt",game.get_combat_snapshot(),[])
	check(arena._shoot(Vector2(600,300),Vector2.RIGHT,cast.packets.projectile,Color.WHITE,0,0,620.0,{"snapshot":cast.snapshot}),"Actual chaos-spell carrier launches before keystone refund")
	old_shot = arena.projectiles[0].duplicate(true)
	check(game.refund_passive(TARGET,game.revision(),path).ok and not game.get_combat_snapshot().has("iron_will"),"Real refund removes rule from future casts")
	check(arena.projectiles[0].snapshot == old_shot.snapshot,"In-flight chaos snapshot retains Will after refund")
	wanted = Damage.resolve(old_shot.payload,old_shot.snapshot.modifiers,{},float(old_shot.snapshot.get("critical_roll",{}).get("multiplier",1.0))).total
	var health_before: float = enemy.health
	arena._update_projectiles(0.25)
	check(arena.damage_trace.size() == 1,"Old chaos carrier settles once after refund")
	close(health_before-float(enemy.health),wanted,"Actual chaos health loss retains frozen8% after refund")
	check(game.allocate_passive(TARGET,0,game.revision(),path).ok,"Re-pay target to restore later refund proof")
	arena.free()
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-iron-will-"): quit(78); return
	source_checks(); arithmetic_checks(); transaction_checks(); await process_frame
	var output := FileAccess.open(OS.get_environment("IRON_WILL_REPORT"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"failed_labels":failures,"evidence":evidence},"\t")+"\n")
	print("IRON_WILL checks=%d failures=%d" % [checks,failures.size()]); quit(1 if not failures.is_empty() else 0)
