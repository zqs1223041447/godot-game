extends SceneTree
const Model = preload("res://scripts/canonical_game_state.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Combat = preload("res://scripts/combat/combat_data.gd")
var checks := 0
var failures := 0
func _initialize()->void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-m1-"): quit(78); return
	var state := Model.new()
	var path := "user://source-tree-%d.json" % Time.get_ticks_usec()
	check(state.save_build(path)==OK,"initial full source save valid")
	check(state.passive_analysis().legal and state.available_passives().size()==6,"all six default Scion first steps playable")
	var initial := state.get_stats()
	check(initial.strength==20 and initial.dexterity==20 and initial.intelligence==20,"source class attributes")
	for id: String in Runtime.Data.adjacency("58833"):
		var before := state.snapshot()
		check(state.allocate_passive(id,0,state.revision(),path).ok,"actual source first-step transaction "+id)
		check(state.talent_points==4 and state.passive_analysis().spent==1,"one source point spent")
		var stats := state.get_stats()
		match id:
			"2151":
				check(stats.intelligence==25 and stats.max_mana==initial.max_mana+2,"intelligence aggregate floor adds real mana")
				check(is_equal_approx(stats.mana_regen,initial.mana_regen*1.2),"raw regeneration percentage executes")
			"15144": check(stats.dexterity==25 and stats.accuracy==initial.accuracy+10 and stats.evasion>initial.evasion and stats.attack_speed>initial.attack_speed,"dexterity and attack speed consumers")
			"47062": check(stats.spell_increased==0.1 and stats.intelligence==25,"spell scope and intelligence")
			"48828": check(stats.physical_increased==0.1 and stats.strength==25 and stats.max_health==initial.max_health+2,"physical component and strength")
			"55373": check(stats.max_health==initial.max_health+14,"flat source life plus aggregate strength")
			"62103": check(stats.projectile_increased==0.1 and stats.dexterity==25,"projectile scope and dexterity")
		check(state.refund_passive(id,state.revision(),path).ok and state.get_stats()==initial,"refund reverses all grants")
		check(state.snapshot().items==before.items and state.snapshot().locations==before.locations,"tree transaction cannot mutate ownership")
	var saved := state.snapshot()
	check(not state.allocate_passive("1",0,state.revision(),path).ok and state.snapshot()==saved,"unknown node atomically rejected")
	check(not state.refund_passive("58833",state.revision(),path).ok and state.snapshot()==saved,"cannot refund own start")
	# Structural legality is insufficient: unsupported source effects block the
	# full node, including nodes with a supported line next to an unsupported one.
	var context := Runtime._context(0,123)
	var reached := {"58833":true}
	var queue: Array[String] = ["58833"]
	var parent := {}
	var blocked_edge := ""
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for adjacent: String in context.adjacency[current]:
			if reached.has(adjacent): continue
			var node: Dictionary=context.nodes[adjacent]
			if node.type in ["start","proxy","mastery"] or node.blighted: continue
			if Runtime.node_effect(adjacent).status != "full":
				if blocked_edge.is_empty(): blocked_edge=adjacent; parent[adjacent]=current
				continue
			reached[adjacent]=true
			parent[adjacent]=current
			queue.append(adjacent)
	check(reached.size()>20 and not blocked_edge.is_empty(),"real source executable paths and blocked frontier exist")
	var candidate := saved.duplicate(true)
	candidate.progress={"level":119,"xp":0}
	var path_ids: Array[String]=[blocked_edge]
	var cursor: String=blocked_edge
	while parent.has(cursor):
		cursor=parent[cursor]
		path_ids.push_front(cursor)
	candidate.talents.allocated=path_ids
	candidate.talents.normal_points=123-(path_ids.size()-1)
	check(not Rules.reason(candidate).is_empty(),"connected partial/unsupported node cannot consume points")
	candidate.talents.allocated.pop_back()
	candidate.talents.normal_points+=1
	check(Rules.reason(candidate).is_empty(),"supported prefix of same real path legal")
	# Source mastery choice and JSON integer restoration are coupled to final save.
	var mastery_id := ""
	var notable_id := ""
	var effect_id := 0
	for id: String in context.nodes:
		if context.nodes[id].type!="mastery": continue
		for notable: String in reached:
			if context.nodes[notable].type=="notable" and context.nodes[notable].group_id==context.nodes[id].group_id:
				for effect: int in context.nodes[id].mastery_effects:
					if Runtime.node_effect(id,effect).status=="full": mastery_id=id;notable_id=notable;effect_id=effect;break
			if not mastery_id.is_empty(): break
		if not mastery_id.is_empty(): break
	check(not mastery_id.is_empty(),"at least one fully executed mastery reachable via original path")
	if not mastery_id.is_empty():
		path_ids=[notable_id]
		cursor=notable_id
		while parent.has(cursor): cursor=parent[cursor];path_ids.push_front(cursor)
		path_ids.append(mastery_id)
		candidate.talents.allocated=path_ids
		candidate.talents.masteries={mastery_id:effect_id}
		candidate.talents.normal_points=123-(path_ids.size()-1)
		check(Rules.reason(candidate).is_empty(),"source mastery candidate accepted")
		var decoded := Rules.decode(JSON.parse_string(JSON.stringify(candidate)))
		check(not decoded.is_empty() and decoded.talents.masteries[mastery_id] is int and Rules.reason(decoded).is_empty(),"JSON restores only declared integral effect field")
		candidate.talents.masteries[mastery_id]=true
		check(Rules.decode(candidate).is_empty(),"boolean mastery value rejected")
	var physical := Damage.packet({"physical":100.0},["hit","attack","projectile"],"basic")
	var melee := Damage.packet({"physical":100.0},["hit","attack","melee"],"basic")
	check(Damage.resolve(physical,Combat.modifiers(initial)).total==100.0,"strength does not leak to projectile physical")
	check(Damage.resolve(melee,Combat.modifiers(initial)).total==104.0,"strength modifier has actual melee-only consumer")
	var frozen := state.get_group_cast("group_000001")
	check(state.allocate_passive("47062",0,state.revision(),path).ok,"spell source allocated")
	check(frozen.snapshot != state.get_group_cast("group_000001").snapshot,"build change invalidates future recipe")
	check(not frozen.snapshot.modifiers.any(func(m: Dictionary):return m.id=="spell_increased"),"prior recipe remains frozen")
	var loaded := Model.new()
	check(loaded.load_build(path) and loaded.snapshot()==state.snapshot() and loaded.get_stats()==state.get_stats(),"source tree and consumers survive actual disk reload")
	var jewels:=Model.new()
	var jewel_path:=path+".jewels"
	check(jewels.save_build(jewel_path)==OK,"source jewel fixture saved")
	for id:String in ["2151","37690","48423","6230"]:
		check(jewels.allocate_passive(id,0,jewels.revision(),jewel_path).ok,"actual source socket path "+id)
	var special:String=jewels.award_special_jewel()
	check(not special.is_empty(),"owned special instance admitted")
	check(jewels.move_item(special,{"kind":"passive_socket","node_id":"6230"},jewels.revision(),jewel_path).ok,"real normally connected source socket accepts jewel")
	check(jewels.available_passives().has("26740"),"actual280 source radius enables disconnected life-regeneration node")
	check(jewels.allocate_passive("26740",0,jewels.revision(),jewel_path).ok and jewels.talent_points==0,"remote allocation still spends last point")
	check(jewels.get_stats().life_regen>0.0,"remote node gives real tick-consumed life regeneration")
	var before:Dictionary=jewels.snapshot()
	var disk_before:=FileAccess.get_file_as_bytes(jewel_path)
	var destination:Dictionary=jewels.first_bag_position(special)
	check(not jewels.move_item(special,destination,jewels.revision(),jewel_path).ok,"cannot remove source of actual remote dependency")
	check(jewels.snapshot()==before and FileAccess.get_file_as_bytes(jewel_path)==disk_before,"dependency reject atomic memory and disk")
	check(not jewels.refund_passive("48423",jewels.revision(),jewel_path).ok,"cannot sever normal path to supporting socket")
	check(jewels.refund_passive("26740",jewels.revision(),jewel_path).ok,"refund dependent remote node")
	check(jewels.move_item(special,destination,jewels.revision(),jewel_path).ok and jewels.location(special).kind=="bag","jewel removable after dependency refunded, same UID")
	print("Source tree runtime: %d checks, %d failures; default reachable fully executed nodes %d" % [checks,failures,reached.size()])
	quit(1 if failures else 0)
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok: failures+=1;push_error(label)
