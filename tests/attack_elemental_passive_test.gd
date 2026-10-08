extends SceneTree
## One source effect; actual paid transactions, compiled packets and native UI data.
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const Locale = preload("res://scripts/passives/source_tree_localization.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Gear = preload("res://scripts/items/equipment_catalog.gd")
const Items = preload("res://scripts/items/unified_item_catalog.gd")
const PassivePanel = preload("res://scripts/ui/canonical_passive_panel.gd")
const LINE := "12% increased Elemental Damage with Attack Skills"
const STAT := "attack_elemental_increased"
const NODES := ["18670","25511","30894","56646","64878"]
const ROUTE := ["50459","45035","59370","63795","38662","5616","39718","56646","25511"]
const PATH := "user://attack-elemental-route.json"
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func close(actual: float, expected: float, label: String) -> void:
	check(is_equal_approx(actual,expected), "%s: %.8f expected %.8f" % [label,actual,expected])
func source_checks() -> void:
	check(Source.line_effect(LINE).grants == [{"stat":STAT,"value":0.12,"mode":"increased"}],"Exact source entry produces one INC grant")
	check(not Patterns.parse_line(LINE,false).supported,"Disabled earlier vocabulary cannot admit the new exact entry")
	for version: int in [19,25,48,49,53,54]:
		check(not Source.line_effect(LINE,version).supported and Source._execution_policy(version) != 55,"Old policy rejects new line: %d" % version)
		check(Source.line_effect(LINE,55).supported,"Interleaved current cache remains independent")
	var occurrences: Array[String] = []
	for id: String in Source.Data.nodes():
		if Source.Data.node(id).stats.has(LINE): occurrences.append(id)
	occurrences.sort()
	check(occurrences == NODES,"Exact effect occurs only in five existing small nodes")
	for id: String in NODES:
		check(Source.Data.node(id).stats == [LINE] and Source.Data.standard_ids().has(id) and Source.node_effect(id).status == "full" and Source.node_effect(id,0,54).status != "full","Existing pure standard node opens only in55: "+id)
	check(not Source.line_effect("24% increased Elemental Damage with Attack Skills",55).supported,"Frozen55 still rejects later notable24% effect")
	for line: String in ["10% increased Elemental Damage with Attack Skills","12% more Elemental Damage with Attack Skills",LINE+" while Chilled",LINE+"."," "+LINE,LINE+"\n"]:
		check(not Source.line_effect(line).supported and Locale.display_line(line).contains(Locale.NOT_IMPLEMENTED),"Other amounts, MORE and conditions stay unsupported: "+line)
	check(Locale.display_line(LINE) == "攻击技能造成的元素伤害提高12%" and Locale.line_status(LINE).implemented,"Chinese copy states element component and has an actual consumer")
	for anchor: Dictionary in Locale.STAT_CONSUMER_GROUPS.damage_and_rates.code_checks:
		check(FileAccess.get_file_as_string("res://"+anchor.path).contains(anchor.contains),"Consumer evidence names production code: "+anchor.path)
func arithmetic_checks() -> void:
	# Gear uses the same existing fractional INC key. Use an actual authored tier.
	var equipment_inc: float = Gear.affix_stat_value(Gear.affix_definition("prismedge"),6)
	close(equipment_inc,0.06,"Existing prismedge percentage normalization")
	var stats := {"global_increased":0.2,"projectile_increased":0.3,"elemental_increased":0.4,STAT:equipment_inc+0.12+0.12}
	var modifiers: Array[Dictionary] = Combat.modifiers(stats)
	var ids: Array[String] = []
	for modifier: Dictionary in modifiers: ids.append(modifier.id)
	check(ids.count(STAT) == 1,"Equipment and two nodes merge into one scoped INC modifier")
	var base := {"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":100.0}
	var packet := {"base":base,"tags":["hit","attack","projectile"]}
	var attack: Dictionary = Damage.resolve(packet,modifiers)
	close(attack.components.physical,150.0,"Physical excludes elemental INC")
	close(attack.components.chaos,150.0,"Chaos excludes elemental INC")
	for type: String in Damage.ELEMENTS: close(attack.components[type],220.0,"Elemental attack adds all INC once: "+type)
	var more: Array[Dictionary] = modifiers.duplicate(true)
	more.append({"id":"more-a","mode":"more","value":0.25,"all_tags":["attack"],"damage_types":[]})
	more.append({"id":"more-b","mode":"more","value":0.1,"all_tags":["attack"],"damage_types":[]})
	close(Damage.resolve(packet,more).components.fire,302.5,"INC sum then independent MORE 1.25 × 1.10")
	close(Damage.resolve({"base":base,"tags":["hit","spell","projectile"]},modifiers).components.fire,190.0,"Projectile spell excludes attack INC")
	close(Damage.resolve({"base":base,"tags":["hit","area","secondary","explosion"]},modifiers).components.fire,160.0,"Independent explosion excludes attack and projectile INC")
	close(Damage.resolve({"base":base,"tags":["hit","attack","melee"]},modifiers).components.fire,190.0,"Melee elemental attack receives same scoped INC")
	var converted_snapshot: Dictionary = Combat.snapshot({"damage":100.0,"physical_to_fire_conversion":0.4,STAT:0.24},[])
	var converted_packet: Dictionary = Combat.event_packet(converted_snapshot,"basic","projectile")
	var converted: Dictionary = Damage.resolve(converted_packet,converted_snapshot.modifiers)
	close(converted.components.physical,60.0,"Conversion remainder receives no elemental INC")
	close(converted.components.fire,49.6,"Converted fire receives elemental INC once")
func transaction_checks() -> void:
	var game := Game.new()
	var candidate: Dictionary = game.snapshot()
	candidate.progress = {"level":4,"xp":0}
	candidate.talents.class_id = 2
	candidate.talents.allocated = [ROUTE[0]]
	candidate.talents.masteries = {}
	candidate.talents.normal_points = 8
	candidate.revision += 1
	check(game._commit(candidate,PATH).ok,"Validated isolated level4 Ranger fixture")
	for id: String in ROUTE.slice(1,7): check(game.allocate_passive(id,0,game.revision(),PATH).ok,"Actual legal prerequisite: "+id)
	var before: Dictionary = game.snapshot()
	var baseline: Dictionary = game.get_combat_snapshot()
	close(game.get_stats()[STAT],0.0,"Before target nodes: no grant")
	check(game.available_passives().has("56646") and before.talents.normal_points == 2,"Real target available with two remaining points")
	var panel := PassivePanel.new()
	root.add_child(panel)
	panel.setup(game,PATH)
	panel._node_clicked("56646",MOUSE_BUTTON_LEFT,false)
	panel._node_hovered("56646",Rect2())
	check(panel._detail.text.contains(Locale.display_line(LINE)) and not panel._detail.text.contains(Locale.NOT_IMPLEMENTED) and not panel._allocate.disabled,"Actual panel copy and allocation button agree")
	check(panel._tree._nodes["56646"].description == Locale.display_line(LINE) and panel._tree._nodes["56646"].status == "implemented" and panel._tree.tooltip_text.contains(Locale.display_line(LINE)),"Actual canvas node and hover copy agree")
	panel._node_clicked("36281",MOUSE_BUTTON_LEFT,false)
	check(panel._detail.text.contains(Locale.NOT_IMPLEMENTED) and panel._allocate.disabled,"Other mixed unimplemented node stays marked and locked")
	var disk: PackedByteArray = FileAccess.get_file_as_bytes(PATH)
	check(DirAccess.make_dir_absolute(PATH+".tmp") == OK,"Inject failed allocation write")
	check(not game.allocate_passive("56646",0,game.revision(),PATH).ok and game.snapshot() == before and FileAccess.get_file_as_bytes(PATH) == disk,"Failed allocation publishes no grant or point spend")
	check(DirAccess.remove_absolute(PATH+".tmp") == OK,"Remove write fault")
	check(game.allocate_passive("56646",0,game.revision(),PATH).ok and game.snapshot().talents.normal_points == 1,"First actual target costs one point")
	close(game.get_stats()[STAT],0.12,"First actual source INC")
	check(game.allocate_passive("25511",0,game.revision(),PATH).ok and game.snapshot().talents.normal_points == 0,"Second actual target costs one point")
	close(game.get_stats()[STAT],0.24,"Two source entries add rather than multiply")
	var after: Dictionary = game.snapshot()
	check(after.items == before.items and after.journey == before.journey,"No items or map progress changes")
	var current: Dictionary = game.get_combat_snapshot()
	actual_hit_checks(game,baseline,current)
	for skill: String in ["tornado","frost","meteor","shade_bolt","cleave"]:
		var old_cast: Dictionary = Compiler.compile_group(skill,baseline,[])
		var new_cast: Dictionary = Compiler.compile_group(skill,current,[])
		check(old_cast.ok and new_cast.ok and old_cast.mana == new_cast.mana and old_cast.cooldown == new_cast.cooldown,"Actual compilation preserves admission, cost and cooldown: "+skill)
		var role := "parent" if skill == "tornado" else "projectile" if skill in ["frost","shade_bolt"] else "direct"
		var old_packet: Dictionary = Combat.event_packet(old_cast.snapshot,skill,role)
		var new_packet: Dictionary = Combat.event_packet(new_cast.snapshot,skill,role)
		var old_damage: Dictionary = Damage.resolve(old_packet,old_cast.snapshot.modifiers)
		var new_damage: Dictionary = Damage.resolve(new_packet,new_cast.snapshot.modifiers)
		if skill == "tornado":
			close(new_damage.components.physical,old_damage.components.physical,"Compiled Tornado physical unchanged")
			close(new_damage.components.fire-old_damage.components.fire,float(old_packet.base.fire)*0.24,"Compiled Tornado fire delta equals one summed INC")
		else: check(new_damage == old_damage,"Compiled nonapplicable skill damage unchanged: "+skill)
	var reopened := Game.new()
	check(reopened.load_build(PATH) and reopened.snapshot() == after and reopened.save_attempts == 0,"Selected55 build reloads without rewrite")
	close(reopened.get_stats()[STAT],0.24,"Selected INC survives reload")
	var forged_old: Dictionary = after.duplicate(true)
	forged_old.version = 54
	check(not Rules.reason_v54(forged_old).is_empty(),"New target allocations cannot enter frozen54")
	check(not game.refund_passive("56646",game.revision(),PATH).ok and game.snapshot() == after,"Bridge prerequisite cannot be refunded")
	check(game.refund_passive("25511",game.revision(),PATH).ok and game.snapshot().talents.normal_points == 1,"Actual leaf refund returns exactly one point")
	close(game.get_stats()[STAT],0.12,"Refund removes one source INC")
	check(game.refund_passive("56646",game.revision(),PATH).ok and game.snapshot().talents.normal_points == 2,"Second actual refund returns exactly one point")
	close(game.get_stats()[STAT],0.0,"All new source INC removed")
	check(reopened.load_build(PATH) and reopened.snapshot() == game.snapshot() and reopened.get_stats()[STAT] == 0.0,"Refunded build reloads without residual grant")
	var equipment_uid := "gear_%06d" % int(game.snapshot().next_item_serial)
	var gear := {"id":equipment_uid,"base_id":"cinder_reed","rarity":"magic","item_level":1,"affixes":[{"id":"prismedge","tier":1,"value":6}]}
	check(game._admit_reward_item(Items.wrap_equipment(gear)) and game.move_item(equipment_uid,{"kind":"equipment","slot_id":"weapon"},game.revision(),PATH).ok,"Equip an actually validated prismedge fixture")
	close(game.get_stats()[STAT],0.06,"Only equipped prismedge INC")
	check(game.allocate_passive("56646",0,game.revision(),PATH).ok and game.allocate_passive("25511",0,game.revision(),PATH).ok,"Reallocate both paid nodes with equipment present")
	close(game.get_stats()[STAT],0.30,"Actual equipment6% + two source12% entries")
	var scoped_count := 0
	for modifier: Dictionary in game.get_combat_snapshot().modifiers:
		if modifier.id == STAT: scoped_count += 1; close(modifier.value,0.30,"One actual aggregated snapshot INC")
	check(scoped_count == 1,"Canonical snapshot has no duplicated source/equipment modifier")
	check(game.refund_passive("25511",game.revision(),PATH).ok and game.refund_passive("56646",game.revision(),PATH).ok,"Actual refunds with equipment retained")
	close(game.get_stats()[STAT],0.06,"Refunds retain only equipment supply")
	panel.queue_free()
func actual_hit_checks(game, baseline: Dictionary, current: Dictionary) -> void:
	var before: Dictionary = game.snapshot()
	var arena = load("res://scenes/main.tscn").instantiate()
	arena.state = game
	arena.build_save_path = PATH
	root.add_child(arena)
	arena.set_process(false)
	arena.hud.set_process(false)
	arena.enemies.clear()
	arena.monster_runtime.reset()
	var enemy: Dictionary = arena._spawn_monster("crawler",Vector2(600,300),"ordinary","normal",[])
	check(not enemy.is_empty(),"Actual scene creates existing ordinary enemy")
	if not enemy.is_empty():
		enemy.spawn = 0.0
		enemy.shield = 0.0
		enemy.armour = 0.0
		enemy.resistances = {}
		for skill: String in ["tornado","frost","meteor"]:
			var role := "parent" if skill == "tornado" else "projectile" if skill == "frost" else "direct"
			var old_cast: Dictionary = Compiler.compile_group(skill,baseline,[])
			var new_cast: Dictionary = Compiler.compile_group(skill,current,[])
			var old_packet: Dictionary = Combat.event_packet(old_cast.snapshot,skill,role)
			var new_packet: Dictionary = Combat.event_packet(new_cast.snapshot,skill,role)
			var lost: Array[float] = []
			for index: int in 2:
				enemy.health = 100000.0
				enemy.max_health = 100000.0
				arena.damage_trace.clear()
				arena._apply_damage_packet(enemy,old_packet if index == 0 else new_packet,old_cast.snapshot if index == 0 else new_cast.snapshot,Color.WHITE,0.0,{"accuracy_checked":true,"cast_id":55,"phase":role})
				check(arena.damage_trace.size() == 1,"One actual admitted-hit settlement: %s/%d" % [skill,index])
				lost.append(100000.0-float(enemy.health))
			close(lost[1]-lost[0],float(old_packet.base.get("fire",0.0))*0.24 if skill == "tornado" else 0.0,"Actual health-loss delta has correct elemental attack scope: "+skill)
		check(game.snapshot() == before,"Isolated admitted hits do not mutate build or talent cost")
	arena.free()
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-attack-elemental-"): quit(78); return
	source_checks()
	arithmetic_checks()
	transaction_checks()
	await process_frame
	print("ATTACK_ELEMENTAL_PASSIVE checks=%d failures=%d" % [checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)
