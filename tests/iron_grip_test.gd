extends "res://tests/attack_elemental_passive_test.gd"
## Reuse the assertion helpers; execute only this finite mechanism/path proof.
const Grip = preload("res://scripts/combat/iron_grip_rules.gd")
const CAPTURE := "res://docs/qa/iron-grip/"
const TARGET := "12926"
const GRIP_LINE := "Strength's Damage bonus applies to Projectile Attack Damage as well as Melee Damage"
const GRIP_ROUTE := ["50459","39821","52904","444","61306","63139","5408","11497","238","10829","16167","19144","28330","46578",TARGET]
var evidence: Array[Dictionary] = []
func check(ok: bool, label: String) -> void:
	evidence.append({"label":label,"ok":ok}); super.check(ok,label)
func captured(value: Variant) -> Variant:
	# Captured JSON restores untyped arrays and JSON numeric representation.
	return JSON.parse_string(JSON.stringify(value,"",true,true))
func source_checks() -> void:
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CAPTURE+"schema56-oracle.json"))
	var frozen := {}
	for key: String in oracle.effects_policy56:
		var parts := key.split(":")
		frozen[key] = Source.node_effect(parts[0],int(parts[1]),56)
	check(captured(frozen) == oracle.effects_policy56,"All4874 frozen56 node/mastery effects exactly match pre-edit production oracle")
	check(Source.line_effect(GRIP_LINE).grants == [{"stat":"iron_grip","value":1.0,"mode":"flat"}],"Exact frozen wording grants only the keystone flag")
	var occurrences: Array[String] = []
	for id: String in Source.Data.nodes():
		if Source.Data.node(id).stats.has(GRIP_LINE): occurrences.append(id)
	check(occurrences == [TARGET],"Only existing keystone12926 contains this exact source line")
	for version: int in [19,38,44,48,55,56]:
		check(Source.node_effect(TARGET,0,version).status == "unsupported" and not Source.line_effect(GRIP_LINE,version).supported,"Frozen old policy rejects12926: %d" % version)
		check(Source.node_effect(TARGET,0,57).status == "full","New cache remains independent of old policy")
	check(not Patterns.parse_line(GRIP_LINE,false).supported,"Disabled prior vocabulary cannot admit Iron Grip")
	for line: String in [GRIP_LINE+"."," "+GRIP_LINE,GRIP_LINE+"\n",GRIP_LINE+" while Chilled","Strength's Damage bonus applies to all Spell Damage as well"]:
		check(not Source.line_effect(line).supported,"Other wording/conditions/spell extension remain rejected: "+line)
	check(Locale.node_name(TARGET) == "铁握持" and Locale.line_status(GRIP_LINE).implemented and not Locale.display_line(GRIP_LINE).contains(Locale.NOT_IMPLEMENTED),"Chinese description uses actual consumer; implemented marker cleared")
	for anchor: Dictionary in Locale.STAT_CONSUMER_GROUPS.iron_grip.code_checks:
		check(FileAccess.get_file_as_string("res://"+anchor.path).contains(anchor.contains),"Consumer evidence points to production code: "+anchor.path)
	for index: int in range(1,GRIP_ROUTE.size()):
		check(Source.Data.adjacency(GRIP_ROUTE[index-1]).has(GRIP_ROUTE[index]),"Actual ordinary graph edge: %s→%s" % [GRIP_ROUTE[index-1],GRIP_ROUTE[index]])
func arithmetic_checks() -> void:
	# Explicit arithmetic fixture: native Strength20 plus OTHER melee30.
	var stats := {"damage":100.0,"strength":100.0,"iron_grip":1.0,"melee_physical_increased":0.5,"physical_increased":0.1,"global_increased":0.1,"projectile_increased":0.2}
	var snapshot: Dictionary = Combat.snapshot(stats,[])
	var packet := {"base":{"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":100.0},"tags":["hit","attack","projectile"],"skill_id":"basic"}
	var resolved: Dictionary = Damage.resolve(packet,snapshot.modifiers)
	close(resolved.components.physical,160.0,"Projectile physical adds only Strength20, excludes other melee30")
	for type: String in ["fire","cold","lightning","chaos"]: close(resolved.components[type],130.0,"Native nonphysical component excludes Strength: "+type)
	packet.tags = ["hit","attack","melee"]
	close(Damage.resolve(packet,snapshot.modifiers).components.physical,170.0,"Existing melee includes native Strength once and retains other melee INC")
	packet.tags.append("projectile")
	close(Damage.resolve(packet,snapshot.modifiers).components.physical,190.0,"Hybrid melee/projectile tags receive native Strength only once")
	for tags: Array in [["hit","spell","projectile"],["hit","secondary","area","explosion"],["hit","projectile"]]:
		packet.tags = tags
		close(Damage.resolve(packet,snapshot.modifiers).components.physical,140.0 if tags.has("projectile") else 120.0,"Physical spell/independent explosion/nonattack excludes Strength extension")
	var more: Array = snapshot.modifiers.duplicate(true)
	more.append({"id":"other-more","mode":"more","value":0.25,"all_tags":["attack"]})
	packet.tags = ["hit","attack","projectile"]
	close(Damage.resolve(packet,more).components.physical,200.0,"Strength remains additive INC before independent MORE")
	for conversion: String in ["physical_to_fire_conversion","physical_to_cold_conversion","physical_to_lightning_conversion"]:
		var converted_stats: Dictionary = stats.duplicate(true); converted_stats[conversion] = 0.4
		converted_stats.attack_added_fire = 100.0
		var cs: Dictionary = Combat.snapshot(converted_stats,[])
		var cp: Dictionary = Combat.event_packet(cs,"basic","projectile")
		var result: Dictionary = Damage.resolve(cp,cs.modifiers)
		var type := conversion.trim_prefix("physical_to_").trim_suffix("_conversion")
		close(result.components.physical,96.0,"Physical conversion remainder retains Strength once: "+type)
		close(result.components[type],64.0+(130.0 if type == "fire" else 0.0),"Converted ancestry inherits Strength; native added fire stays separate: "+type)
		cp.tags.append("melee")
		close(Damage.resolve(cp,cs.modifiers).components.physical,114.0,"Converted hybrid excludes duplicate Strength: "+type)
		cp.tags = ["hit","spell","projectile"]
		close(Damage.resolve(cp,cs.modifiers).components.physical,84.0,"Even converted physical spell excludes Strength: "+type)
	var all: Dictionary = stats.duplicate(true)
	all.physical_to_fire_conversion = 0.4; all.physical_to_cold_conversion = 0.4; all.physical_to_lightning_conversion = 0.4
	var all_snapshot: Dictionary = Combat.snapshot(all,[])
	var all_damage: Dictionary = Damage.resolve(Combat.event_packet(all_snapshot,"tornado","parent"),all_snapshot.modifiers)
	close(all_damage.components.fire,84.0,"Normalized three-way physical ancestry20×1.6 plus native fire40×1.3")
	close(all_damage.components.cold,32.0,"Three-way converted cold only")
	close(all_damage.components.lightning,32.0,"Three-way converted lightning only")
	for strength: float in [0.0,4.0,5.0,9.0,10.0,44.0,54.0]:
		var boundary: Dictionary = Combat.snapshot({"damage":100.0,"strength":strength,"iron_grip":1.0},[])
		close(Damage.resolve(Combat.event_packet(boundary,"basic","projectile"),boundary.modifiers).total,100.0+floorf(strength/5.0),"Existing Strength five-point staircase preserved: %.0f" % strength)
	var inactive: Dictionary = Combat.snapshot({"damage":100.0,"strength":100.0},[])
	check(not inactive.has("iron_grip") and not Combat.snapshot({"damage":100.0,"strength":100.0,"iron_grip":0.0},[]).has("iron_grip"),"Absent/zero flag leaves old snapshot shape untouched")
	for flag: Variant in [true,-1.0,0.5,NAN,INF]:
		check(not Compiler.compile_basic(Combat.snapshot({"damage":100.0,"strength":100.0,"iron_grip":flag},[])).ok,"Malformed source flag cannot silently enable rule")
	var invalid: Dictionary = snapshot.duplicate(true); invalid.iron_grip.strength_physical_increased = 0.5
	check(not Compiler.compile_basic(invalid).ok,"Context cannot substitute aggregate melee INC for Strength source")
	invalid = snapshot.duplicate(true); invalid.modifiers[-1].excluded_tags = ["unknown"]
	check(not Compiler.compile_basic(invalid).ok,"Exclusion predicate validates tags at compiler boundary")
func transaction_checks() -> void:
	var path := "user://build_save.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(CAPTURE+"schema56-town.json")); file.close()
	var game := Game.new()
	check(game.load_build(path) and game.level == 11 and game.talent_points == 2,"Actual75-root earned fixture loads with13 paid predecessors and two remaining points")
	var old_stats: Dictionary = game.get_stats()
	var before: Dictionary = game.snapshot()
	var baseline: Dictionary = game.get_combat_snapshot()
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CAPTURE+"schema56-oracle.json"))
	check(captured(old_stats) == oracle.stats and captured(baseline) == oracle.snapshot,"Inactive stats and snapshot exactly match pre-edit56 production")
	for skill: String in oracle.casts:
		var cast: Dictionary = Compiler.compile_basic(baseline) if skill == "basic" else Compiler.compile_group(skill,baseline,[])
		var role := "parent" if skill == "tornado" else "direct" if skill == "cleave" else "projectile"
		check(cast.ok and captured(cast.snapshot) == oracle.casts[skill].snapshot and captured(Damage.resolve(Combat.event_packet(cast.snapshot,skill,role),cast.snapshot.modifiers)) == oracle.casts[skill].damage,"Inactive compiled packet/result matches baseline: "+skill)
	var panel := PassivePanel.new(); root.add_child(panel); panel.setup(game,path)
	panel._node_clicked(TARGET,MOUSE_BUTTON_LEFT,false); panel._node_hovered(TARGET,Rect2())
	check(not panel._allocate.disabled and panel._detail.text.contains("铁握持") and not panel._detail.text.contains(Locale.NOT_IMPLEMENTED) and panel._tree._nodes[TARGET].status == "implemented","Actual detail/canvas/allocate button agree")
	var disk := FileAccess.get_file_as_bytes(path)
	check(DirAccess.make_dir_absolute(path+".tmp") == OK,"Inject isolated final allocation write fault")
	check(not game.allocate_passive(TARGET,0,game.revision(),path).ok and game.snapshot() == before and game.get_combat_snapshot() == baseline and FileAccess.get_file_as_bytes(path) == disk,"Failed allocation spends no point, publishes no rule, preserves file/snapshot")
	check(DirAccess.remove_absolute(path+".tmp") == OK,"Remove only isolated allocation fault")
	var saves: int = game.successful_saves
	panel._allocate.pressed.emit()
	check(game.snapshot().talents.allocated == GRIP_ROUTE and game.talent_points == 1 and game.successful_saves == saves+1,"Actual button pays14th point exactly once")
	var after: Dictionary = game.snapshot()
	var current: Dictionary = game.get_combat_snapshot()
	for field: String in Rules.FIELDS:
		if field not in ["talents","revision"]: check(after[field] == before[field],"Allocation preserves unrelated saved field: "+field)
	var new_stats: Dictionary = game.get_stats(); new_stats.erase("iron_grip")
	check(new_stats == old_stats,"Keystone adds only rule flag; all attribute and native melee/resource benefits unchanged")
	for skill: String in ["basic","tornado","cleave","frost"]:
		var old_cast: Dictionary = Compiler.compile_basic(baseline) if skill == "basic" else Compiler.compile_group(skill,baseline,[])
		var new_cast: Dictionary = Compiler.compile_basic(current) if skill == "basic" else Compiler.compile_group(skill,current,[])
		check(old_cast.ok and new_cast.ok,"Actual relevant skill compilation: "+skill)
		var roles: Array = ["parent","child","secondary"] if skill == "tornado" else ["direct"] if skill == "cleave" else ["projectile"]
		for role: String in roles:
			var op: Dictionary = Combat.event_packet(old_cast.snapshot,skill,role)
			var np: Dictionary = Combat.event_packet(new_cast.snapshot,skill,role)
			var od: Dictionary = Damage.resolve(op,old_cast.snapshot.modifiers)
			var nd: Dictionary = Damage.resolve(np,new_cast.snapshot.modifiers)
			if skill in ["basic","tornado"] and role != "secondary":
				close(nd.components.physical-od.components.physical,float(op.base.physical)*0.08,"Actual Strength44 gives one8%% physical INC: %s/%s" % [skill,role])
				close(nd.components.get("fire",0.0),od.components.get("fire",0.0),"Actual native fire unchanged: %s/%s" % [skill,role])
			else: check(nd == od,"Actual melee/spell/independent explosion unchanged: %s/%s" % [skill,role])
	actual_hit_checks(game,baseline,current)
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == after and reopened.save_attempts == 0 and reopened.get_combat_snapshot() == current,"Allocated57 reloads without rewrite")
	var forged: Dictionary = after.duplicate(true); forged.version = 56
	check(not Rules.reason_v56(forged).is_empty() and Rules.decode_v56(JSON.parse_string(JSON.stringify(forged))).is_empty(),"Old56 legal set cannot be expanded by injecting target allocation")
	check(not game.refund_passive("46578",game.revision(),path).ok and game.snapshot() == after,"Original bridge refund legality preserved")
	flight_checks(game,path,current)
	check(game.snapshot().talents == after.talents and game.get_combat_snapshot() == current,"Strength flight test restores only its paid node/target, with exact original point balance")
	after = game.snapshot()
	disk = FileAccess.get_file_as_bytes(path)
	check(DirAccess.make_dir_absolute(path+".tmp") == OK,"Inject isolated refund write fault")
	check(not game.refund_passive(TARGET,game.revision(),path).ok and game.snapshot() == after and FileAccess.get_file_as_bytes(path) == disk,"Failed refund keeps point, flag and save")
	check(DirAccess.remove_absolute(path+".tmp") == OK,"Remove isolated refund fault")
	check(game.refund_passive(TARGET,game.revision(),path).ok and game.talent_points == 2 and game.get_stats() == old_stats and game.get_combat_snapshot() == baseline,"Successful leaf refund returns one point and exact original stats/snapshot")
	panel.queue_free()
func arena_for(game, path: String):
	var arena = load("res://scenes/main.tscn").instantiate(); arena.state = game; arena.build_save_path = path
	root.add_child(arena); arena.set_process(false); arena.hud.set_process(false); arena.auto_fire = false
	arena.enemies.clear(); arena.monster_runtime.reset()
	return arena
func actual_hit_checks(game, baseline: Dictionary, current: Dictionary) -> void:
	var arena = arena_for(game,"user://build_save.json")
	var enemy: Dictionary = arena._spawn_monster("crawler",Vector2(600,300),"ordinary","normal",[])
	check(not enemy.is_empty(),"Actual Main creates admitted finite hit target")
	if enemy.is_empty(): arena.free(); return
	enemy.spawn = 0.0; enemy.shield = 0.0; enemy.armour = 0.0; enemy.resistances = {}
	for skill: String in ["basic","tornado","cleave","frost"]:
		var role := "parent" if skill == "tornado" else "direct" if skill == "cleave" else "projectile"
		var losses: Array[float] = []
		var physical_base := 0.0
		for source: Dictionary in [baseline,current]:
			var cast: Dictionary = Compiler.compile_basic(source) if skill == "basic" else Compiler.compile_group(skill,source,[])
			var packet: Dictionary = Combat.event_packet(cast.snapshot,skill,role)
			physical_base = float(packet.base.get("physical",0.0))
			enemy.health = 100000.0; enemy.max_health = 100000.0; arena.damage_trace.clear()
			arena._apply_damage_packet(enemy,packet,cast.snapshot,Color.WHITE,0.0,{"accuracy_checked":true,"cast_id":57,"phase":role})
			check(arena.damage_trace.size() == 1,"Actual Main settles one finite admitted hit: "+skill)
			losses.append(100000.0-float(enemy.health))
		close(losses[1]-losses[0],physical_base*0.08 if skill in ["basic","tornado"] else 0.0,"Real health-loss scope: "+skill)
	arena.free()
func flight_checks(game, path: String, current: Dictionary) -> void:
	var arena = arena_for(game,path)
	var enemy: Dictionary = arena._spawn_monster("crawler",Vector2(700,300),"ordinary","normal",[])
	check(not enemy.is_empty(),"Actual Main flight target exists")
	if enemy.is_empty(): arena.free(); return
	enemy.spawn = 0.0; enemy.shield = 0.0; enemy.armour = 0.0; enemy.resistances = {}; enemy.evasion = 0.0
	enemy.health = 100000.0; enemy.max_health = 100000.0
	var cast: Dictionary = Compiler.compile_basic(current)
	check(arena._shoot(Vector2(600,300),Vector2.RIGHT,cast.packets.projectile,Color.WHITE,0,0,600.0,{"snapshot":cast.snapshot}),"Actual projectile launched before Strength change")
	var shot: Dictionary = arena.projectiles[0].duplicate(true)
	var strength_node := ""
	for id: String in game.available_passives():
		if Source.Data.node(id).stats == ["+10 to Strength"]: strength_node = id; break
	check(not strength_node.is_empty() and game.allocate_passive(strength_node,0,game.revision(),path).ok,"Final earned point legally buys an existing adjacent Strength+10 node: "+strength_node)
	close(game.get_stats().strength,54.0,"Final Strength changes44→54 via real paid node")
	close(game.get_combat_snapshot().iron_grip.strength_physical_increased,0.10,"Next snapshot has new native10%")
	check(arena.projectiles[0].snapshot == shot.snapshot and arena.projectiles[0].payload == shot.payload,"In-flight packet/snapshot unchanged by successful Strength transaction")
	var wanted: float = Damage.resolve(shot.payload,shot.snapshot.modifiers,{},float(shot.snapshot.get("critical_roll",{}).get("multiplier",1.0))).total
	var new_cast: Dictionary = game.get_basic_cast()
	check(arena._shoot(Vector2(600,300),Vector2.RIGHT,new_cast.packets.projectile,Color.WHITE,0,0,600.0,{"snapshot":new_cast.snapshot}),"Actual next projectile launches with Strength54")
	var newer: Dictionary = arena.projectiles[1].duplicate(true)
	var new_wanted: float = Damage.resolve(newer.payload,newer.snapshot.modifiers,{},float(newer.snapshot.get("critical_roll",{}).get("multiplier",1.0))).total
	arena._update_projectiles(0.25)
	check(arena.damage_trace.size() == 2,"Old and new projectiles follow real contact/settlement path")
	close(arena.damage_trace[0].total,wanted,"Old in-flight health loss uses frozen8%, not current10%")
	close(arena.damage_trace[1].total,new_wanted,"Next projectile uses frozen new10%")
	close(100000.0-float(enemy.health),wanted+new_wanted,"Both actual carrier settlements produce exact health loss")
	check(game.refund_passive(strength_node,game.revision(),path).ok,"Refund only the test's paid Strength branch")
	arena.projectiles.clear(); arena.damage_trace.clear()
	cast = game.get_basic_cast()
	check(arena._shoot(Vector2(600,300),Vector2.RIGHT,cast.packets.projectile,Color.WHITE,0,0,600.0,{"snapshot":cast.snapshot}),"Actual carrier launches before keystone refund")
	var refund_shot: Dictionary = arena.projectiles[0].duplicate(true)
	check(game.refund_passive(TARGET,game.revision(),path).ok,"Temporarily refund target during flight")
	check(shot.snapshot.iron_grip.strength_physical_increased == 0.08 and not game.get_combat_snapshot().has("iron_grip"),"Captured carrier retains keystone after refund; future casts lose rule")
	check(arena.projectiles[0].snapshot == refund_shot.snapshot,"Active in-flight snapshot unchanged by keystone refund")
	wanted = Damage.resolve(refund_shot.payload,refund_shot.snapshot.modifiers,{},float(refund_shot.snapshot.get("critical_roll",{}).get("multiplier",1.0))).total
	var old_health: float = enemy.health
	arena._update_projectiles(0.25)
	check(arena.damage_trace.size() == 1,"Refunded keystone's old carrier still settles once")
	close(old_health-float(enemy.health),wanted,"Actual old-flight health loss retains8% after keystone refund")
	check(game.allocate_passive(TARGET,0,game.revision(),path).ok,"Restore paid target for remaining refund proof")
	arena.free()
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-iron-grip-"): quit(78); return
	source_checks(); arithmetic_checks(); transaction_checks(); await process_frame
	var output := FileAccess.open(OS.get_environment("IRON_GRIP_REPORT"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"failed_labels":failures,"evidence":evidence},"\t")+"\n")
	print("IRON_GRIP checks=%d failures=%d" % [checks,failures.size()]); quit(1 if not failures.is_empty() else 0)
