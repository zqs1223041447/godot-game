extends "res://tests/attack_elemental_passive_test.gd"
## Reuse assertions and the existing actual-hit helper, not the old suite entry.
const TARGET := "24% increased Elemental Damage with Attack Skills"
const NOTABLE := "15842"
const NOTABLE_ROUTE := ["50459","39821","52904","444","61306","54142","30894",NOTABLE]
const EARNED := "res://docs/qa/v115-native-map-entry/earned-v114-save.json"
const ORACLE := "res://docs/qa/one-with-nature/schema55-oracle.json"
var evidence: Array[Dictionary] = []
func check(ok: bool, label: String) -> void:
	evidence.append({"label":label,"ok":ok})
	super.check(ok,label)
func source_checks() -> void:
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORACLE))
	check(Source.line_effect(TARGET).grants == [{"stat":STAT,"value":0.24,"mode":"increased"}],"Only exact24% source yields existing INC")
	var occurrences: Array[String] = []
	for id: String in Source.Data.nodes():
		if Source.Data.node(id).stats.has(TARGET): occurrences.append(id)
	check(occurrences == [NOTABLE],"Exact24% occurs in one existing standard notable")
	for id: String in oracle.nodes_policy55:
		check(Source.node_effect(id,0,55) == oracle.nodes_policy55[id],"Frozen55 node matches captured baseline: "+id)
	for version: int in [19,25,48,49,53,54,55]:
		check(not Source.line_effect(TARGET,version).supported and Source.node_effect(NOTABLE,0,version).status == "partial","Historical policy rejects target: %d" % version)
		check(Source.node_effect(NOTABLE,0,56).status == "full","Interleaved56 cache remains independent")
	check(Source.line_effect(LINE,55).grants == Source.line_effect(LINE,56).grants,"Prior exact12% unchanged across55/56")
	check(not Patterns.parse_line(TARGET,false).supported,"Disabled prior vocabulary cannot admit new effect")
	for line: String in ["20% increased Elemental Damage with Attack Skills","25% increased Elemental Damage with Attack Skills","24% more Elemental Damage with Attack Skills",TARGET+" while Chilled",TARGET+"."," "+TARGET,TARGET+"\n"]:
		check(not Source.line_effect(line).supported and Locale.display_line(line).contains(Locale.NOT_IMPLEMENTED),"Other amounts/conditions/MORE stay unsupported: "+line)
	check(Locale.node_name(NOTABLE) == "与自然合一" and Locale.display_line(TARGET) == "攻击技能造成的元素伤害提高24%" and Locale.line_status(TARGET).implemented,"Exact approved name and effect display agree with executor")
	var effect: Dictionary = Source.node_effect(NOTABLE)
	check(effect.grants == [{"stat":"fire_resistance","value":0.08,"mode":"flat"},{"stat":"cold_resistance","value":0.08,"mode":"flat"},{"stat":"lightning_resistance","value":0.08,"mode":"flat"},{"stat":"attack_crit_chance_increased","value":0.24,"mode":"increased"},{"stat":STAT,"value":0.24,"mode":"increased"}],"Existing resistance and attack-critical grants preserved exactly once")
func arithmetic_checks() -> void:
	var mods: Array[Dictionary] = Combat.modifiers({"global_increased":0.20,STAT:0.06+0.12+0.24})
	var base := {"physical":100.0,"fire":100.0,"cold":100.0,"lightning":100.0,"chaos":100.0}
	var packet := {"base":base,"tags":["hit","attack","projectile"]}
	var damage: Dictionary = Damage.resolve(packet,mods)
	for type: String in Damage.ELEMENTS: close(damage.components[type],162.0,"Elemental attack equipment6 + source12 + notable24 + global20 INC: "+type)
	for type: String in ["physical","chaos"]: close(damage.components[type],120.0,"Non-elemental excludes scoped INC: "+type)
	mods.append({"id":"more-a","mode":"more","value":0.25,"all_tags":["attack"],"damage_types":[]})
	mods.append({"id":"more-b","mode":"more","value":0.10,"all_tags":["attack"],"damage_types":[]})
	close(Damage.resolve(packet,mods).components.fire,222.75,"Summed INC precedes independent MORE1.25 ×1.10")
	for tags: Array in [["hit","spell","projectile"],["hit","area","secondary","explosion"]]:
		close(Damage.resolve({"base":base,"tags":tags},mods).components.fire,120.0,"Spell/independent explosion excludes attack INC and MORE")
	close(Damage.resolve({"base":base,"tags":["hit","attack","melee"]},mods).components.cold,222.75,"Same scope applies to elemental melee attack")
	var frozen: Dictionary = Combat.snapshot({"damage":100.0,"physical_to_fire_conversion":0.4,STAT:0.42},[])
	var result: Dictionary = Damage.resolve(Combat.event_packet(frozen,"basic","projectile"),frozen.modifiers)
	close(result.components.physical,60.0,"Converted attack physical remainder unchanged")
	close(result.components.fire,56.8,"Converted elemental portion receives summed INC once")
func transaction_checks() -> void:
	var file := FileAccess.open(PATH,FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(EARNED)); file.close()
	var game := Game.new()
	check(game.load_build(PATH) and game.snapshot().progress.level == 5,"Existing earned level5 load; no point or currency injection")
	var earned_points: int = game.talent_points
	check(game.select_class(2,game.revision(),PATH).ok,"Actual Ranger selection")
	for id: String in NOTABLE_ROUTE.slice(1,7): check(game.allocate_passive(id,0,game.revision(),PATH).ok,"Paid existing prerequisite: "+id)
	check(game.talent_points == earned_points-6 and game.available_passives().has(NOTABLE),"Six paid prerequisites expose target; total route costs seven")
	var uid := "gear_%06d" % int(game.snapshot().next_item_serial)
	var gear := {"id":uid,"base_id":"runewood_focus","rarity":"rare","item_level":1,"affixes":[{"id":"prismedge","tier":1,"value":6},{"id":"attack_added_fire","tier":1,"value":2},{"id":"coalglow","tier":1,"value":6},{"id":"rimeecho","tier":1,"value":6}]}
	var valid: bool = Gear.validate_instance(gear)
	check(valid,"Explicit four-affix rare fixture obeys existing rarity/slot/tier bounds")
	if not valid: return
	var admitted: bool = game._admit_reward_item(Items.wrap_equipment(gear))
	check(admitted,"Existing reward admission owns explicit equipment fixture")
	if not admitted: return
	var equipped: Dictionary = game.move_item(uid,{"kind":"equipment","slot_id":"weapon"},game.revision(),PATH)
	check(equipped.ok,"Actual equipment transaction supplies6% INC and attack-added fire: "+str(equipped.reason))
	if not equipped.ok: return
	close(game.get_stats()[STAT],0.18,"Before notable: actual equipment6 + prior node12")
	var before: Dictionary = game.snapshot()
	var old_stats: Dictionary = game.get_stats()
	var baseline: Dictionary = game.get_combat_snapshot()
	var panel := PassivePanel.new(); root.add_child(panel); panel.setup(game,PATH)
	panel._node_clicked(NOTABLE,MOUSE_BUTTON_LEFT,false); panel._node_hovered(NOTABLE,Rect2())
	check(not panel._allocate.disabled and not panel._detail.text.contains(Locale.NOT_IMPLEMENTED) and panel._detail.text.contains("与自然合一"),"Actual panel enables legal target and shows approved name")
	check(panel._tree._nodes[NOTABLE].status == "implemented" and panel._tree._nodes[NOTABLE].description.contains(Locale.display_line(TARGET)),"Actual canvas/tooltip description agrees")
	var disk := FileAccess.get_file_as_bytes(PATH)
	check(DirAccess.make_dir_absolute(PATH+".tmp") == OK,"Inject final allocation write failure")
	check(not game.allocate_passive(NOTABLE,0,game.revision(),PATH).ok and game.snapshot() == before and game.get_combat_snapshot() == baseline and FileAccess.get_file_as_bytes(PATH) == disk,"Write failure spends no point and publishes no grant or snapshot")
	check(DirAccess.remove_absolute(PATH+".tmp") == OK,"Remove only isolated test write fault")
	var saves: int = game.successful_saves
	panel._allocate.pressed.emit()
	check(game.snapshot().talents.allocated == NOTABLE_ROUTE and game.talent_points == earned_points-7 and game.successful_saves == saves+1,"Actual allocation button commits seven-point route once")
	close(game.get_stats()[STAT],0.42,"Actual equipment6 + prior12 + target24 INC sums")
	for resistance: String in ["fire_resistance","cold_resistance","lightning_resistance"]:
		close(game.get_stats()[resistance]-old_stats[resistance],0.08,"Existing notable resistance retained: "+resistance)
	close(game.get_stats().attack_crit_chance_increased-old_stats.attack_crit_chance_increased,0.24,"Existing attack critical increase retained")
	var after: Dictionary = game.snapshot()
	for field: String in ["items","locations","skill_groups","bindings","progress","crafting","journey","migration_ledger","next_item_serial"]:
		check(after[field] == before[field],"Node allocation preserves unrelated canonical field: "+field)
	var current: Dictionary = game.get_combat_snapshot()
	actual_hit_checks(game,baseline,current)
	for skill: String in ["basic","tornado","cleave","frost","meteor","shade_bolt"]:
		var old_cast: Dictionary = Compiler.compile_basic(baseline) if skill == "basic" else Compiler.compile_group(skill,baseline,[])
		var new_cast: Dictionary = Compiler.compile_basic(current) if skill == "basic" else Compiler.compile_group(skill,current,[])
		check(old_cast.ok and new_cast.ok,"Actual existing skill compiles: "+skill)
		var role := "parent" if skill == "tornado" else "projectile" if skill in ["basic","frost","shade_bolt"] else "direct"
		var op: Dictionary = Combat.event_packet(old_cast.snapshot,skill,role)
		var np: Dictionary = Combat.event_packet(new_cast.snapshot,skill,role)
		var od: Dictionary = Damage.resolve(op,old_cast.snapshot.modifiers)
		var nd: Dictionary = Damage.resolve(np,new_cast.snapshot.modifiers)
		if skill in ["basic","tornado","cleave"]:
			check(op.base.get("fire",0.0)>0.0,"Actual attack contains elemental component: "+skill)
			close(nd.components.fire-od.components.fire,float(op.base.fire)*0.24,"Compiled actual attack fire delta is one additive24: "+skill)
			close(nd.components.physical,od.components.physical,"Actual physical component unaffected: "+skill)
			close(new_cast.snapshot.critical.primary.chance-old_cast.snapshot.critical.primary.chance,0.012,"Existing notable crit increases base5% chance by1.2pp: "+skill)
		else: check(nd == od and new_cast.snapshot.critical == old_cast.snapshot.critical,"Actual spell damage and critical policy unchanged: "+skill)
	var old_secondary: Dictionary = Compiler.compile_group("tornado",baseline,[])
	var new_secondary: Dictionary = Compiler.compile_group("tornado",current,[])
	check(Damage.resolve(Combat.secondary_packet(old_secondary.snapshot,"tornado"),old_secondary.snapshot.modifiers) == Damage.resolve(Combat.secondary_packet(new_secondary.snapshot,"tornado"),new_secondary.snapshot.modifiers),"Actual Tornado independent explosion unchanged")
	var reopened := Game.new()
	check(reopened.load_build(PATH) and reopened.snapshot() == after and reopened.save_attempts == 0 and reopened.get_combat_snapshot() == current,"Selected56 route/save/stats reopen without rewrite")
	var forged: Dictionary = after.duplicate(true); forged.version = 55
	check(not Rules.reason_v55(forged).is_empty() and Rules.decode_v55(JSON.parse_string(JSON.stringify(forged))).is_empty(),"New allocation cannot enter frozen55 validation or decoder")
	check(game.refund_passive(NOTABLE,game.revision(),PATH).ok and game.talent_points == earned_points-6,"Actual leaf refund returns one point")
	close(game.get_stats()[STAT],0.18,"Refund retains equipment6 and prior12")
	for resistance: String in ["fire_resistance","cold_resistance","lightning_resistance","attack_crit_chance_increased"]:
		close(game.get_stats()[resistance],old_stats[resistance],"Refund removes only notable grant: "+resistance)
	panel.queue_free()
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-one-with-nature-"): quit(78); return
	var fixture_sha := FileAccess.get_sha256(EARNED)
	source_checks(); arithmetic_checks(); transaction_checks()
	check(FileAccess.get_sha256(EARNED) == fixture_sha,"Original earned fixture immutable")
	await process_frame
	var report_path := OS.get_environment("ONE_WITH_NATURE_REPORT")
	if not report_path.is_empty():
		var output := FileAccess.open(report_path,FileAccess.WRITE)
		output.store_string(JSON.stringify({"checks":checks,"failures":failures.size(),"failed_labels":failures,"evidence":evidence,"earned_fixture_sha256":fixture_sha},"\t")+"\n")
	print("ONE_WITH_NATURE_PASSIVE checks=%d failures=%d" % [checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)
