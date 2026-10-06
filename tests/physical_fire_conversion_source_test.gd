extends SceneTree
## Exact source gate, complete mastery ownership and actual allocation/refund transactions.
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const ENTRY := "40% of Physical Damage Converted to Fire Damage"
const GRANTS := [{"stat":"physical_to_fire_conversion","value":0.4,"mode":"flat"}]
const ENTRANCES := ["11505","19749","34927","37911","38320","40271","48267","63268"]
const GATEWAYS := {"11505":"29049","63268":"24324","48267":"2550","34927":"11924"}
const BLOCKED := ["38320","37911","19749","40271"]
const ROOT := "res://docs/qa/v069-migration/"
var checks := 0
var failures := 0
var evidence := {"routes":{},"source_effects_compared":0,"opened_mastery_choices":[]}


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok


func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func candidate(ids: Array, choices: Dictionary = {}, version: int = 44) -> Dictionary:
	var result := Game.new().snapshot()
	result.version = version
	result.progress = {"level":119,"xp":0}
	result.talents.class_id = 0
	result.talents.allocated = ids.duplicate()
	result.talents.masteries = choices.duplicate()
	result.talents.normal_points = 124-ids.size()
	return result


func supported_paths() -> Dictionary:
	var graph := Source._context(0,123)
	var parents := {"58833":""}
	var queue: Array[String] = ["58833"]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		for neighbor: String in graph.adjacency[id]:
			var node: Dictionary = graph.nodes[neighbor]
			if parents.has(neighbor) or node.type in ["start","proxy","mastery"] or node.blighted or Source.node_effect(neighbor).status != "full": continue
			parents[neighbor] = id
			queue.append(neighbor)
	return parents


func route(parents: Dictionary, gateway: String) -> Array[String]:
	var result: Array[String] = []
	var cursor := gateway
	while not cursor.is_empty(): result.push_front(cursor); cursor = parents[cursor]
	return result


func parser_checks() -> void:
	check(Source.CURRENT_SAVE_VERSION == 44 and Source.PHYSICAL_FIRE_CONVERSION_SAVE_VERSION == 44, "Only source44 opens conversion")
	check(Patterns.parse_line(ENTRY).grants == GRANTS, "Exact original mastery entry grants precisely40%")
	check(not Patterns.parse_line(ENTRY,true,true,true,true,true,true,true,true,true,true,true,true,true,false).supported, "Explicit conversion vocabulary gate closes entry")
	check(not Patterns.parse_line(ENTRY,false).supported, "Older prerequisite vocabulary closes entry")
	for version: int in range(14,44):
		check(not Source.line_effect(ENTRY,version).supported and Source.line_effect(ENTRY,44).grants == GRANTS and not Source.line_effect(ENTRY,version).supported, "Interleaved current and frozen caches isolate version%d" % version)
	check(Source._execution_policy(40) == 40 and Source._execution_policy(41) == 41 and Source._execution_policy(42) == 41 and Source._execution_policy(43) == 41, "All pre44 source policies remain frozen")
	for bad: Variant in [null,[],{},true,40,NAN,INF,"",ENTRY+"."," "+ENTRY,ENTRY+" ",ENTRY+"\n",ENTRY+"\r",ENTRY+" while on Full Life",ENTRY.replace("40%","50%"),ENTRY.replace("40%","40.0%"),ENTRY.replace("Physical","physical"),ENTRY.replace("Fire","Cold"),ENTRY.replace("Fire","Lightning"),"Gain 40% of Physical Damage as Extra Fire Damage","50% of Physical, Cold and Lightning Damage Converted to Fire Damage\nDeal no Non-Fire Damage"]:
		var parsed := Patterns.parse_line(bad)
		check(not parsed.supported and parsed.grants.is_empty(), "Malformed, conditional, other conversion and extra damage stay closed: "+str(bad))
	var detached := Source.line_effect(ENTRY)
	detached.grants[0].value = 9.0
	check(Source.line_effect(ENTRY).grants == GRANTS, "Returned grant cannot mutate source cache")
	check(Localization.line_status(ENTRY).implemented, "Consumer-backed localized source line is implemented")


func source_closure() -> void:
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"fixtures/v43-oracle.json"))
	var opened: Array[String] = []
	for key: String in oracle.source_effects:
		var parts := key.split(":")
		var id := parts[0]
		var choice := int(parts[1])
		check(digest(var_to_bytes(Source.node_effect(id,choice,43))) == oracle.source_effects[key], "Every old43 node and choice remains byte-identical: "+key)
		var current := Source.node_effect(id,choice,44)
		if choice == 65020 and ENTRANCES.has(id):
			check(current.status == "full" and current.grants == GRANTS and current.supported == [ENTRY] and current.unsupported.is_empty(), "Whole selected mastery65020 is implemented: "+id)
			opened.append(id)
		else: check(digest(var_to_bytes(current)) == oracle.source_effects[key], "No other complete or partial source effect changes: "+key)
		evidence.source_effects_compared += 1
	opened.sort()
	check(opened == ENTRANCES, "Exactly eight entrances open one unique effect65020")
	evidence.opened_mastery_choices = opened
	for id: String in Source.Data.standard_ids():
		if Source.Data.node(id).name == "Avatar of Fire": check(Source.node_effect(id).status != "full", "Avatar of Fire remains blocked as a whole")
	var parents := supported_paths()
	for id: String in BLOCKED:
		var has_gateway := false
		for node_id: String in parents:
			var node := Source.Data.node(node_id)
			if node.type == "notable" and node.group_id == Source.Data.node(id).group_id: has_gateway = true
		check(not has_gateway, "Unsupported notable group cannot unlock entrance: "+id)


func transaction_checks() -> void:
	var parents := supported_paths()
	for mastery: String in GATEWAYS:
		var gateway: String = GATEWAYS[mastery]
		if not check(parents.has(gateway), "Supported path reaches original notable"+gateway): continue
		var ids := route(parents,gateway)
		evidence.routes[mastery] = ids
		var game := Game.new()
		game._accept_memory(candidate(["58833"]))
		var path := "user://source44-"+mastery+".json"
		if not check(game.save_build(path) == OK, "Create isolated actual allocation fixture"): continue
		for id: String in ids.slice(1):
			if not check(game.allocate_passive(id,0,game.revision(),path).ok, "Actual source allocation through supported original edge: "+id): return
		check(game.available_passives().has(mastery), "Original allocated notable unlocks mastery entrance: "+mastery)
		for blocked: String in BLOCKED: check(not game.available_passives().has(blocked), "Unimplemented notable group remains unavailable: "+blocked)
		var before := game.snapshot()
		var stats := game.get_stats()
		var snapshot := game.get_combat_snapshot()
		var points := game.talent_points
		check(not stats.has("physical_to_fire_conversion") and not snapshot.has("physical_to_fire_conversion"), "Unselected build carries no new stat or snapshot fields")
		if not check(game.allocate_passive(mastery,65020,game.revision(),path).ok, "Actual mastery65020 transaction: "+mastery): return
		check(game.talent_points == points-1 and is_equal_approx(game.get_stats().get("physical_to_fire_conversion",0.0),0.4), "Selecting one source choice spends one point and grants exactly40%")
		check(game.snapshot().items == before.items and game.snapshot().locations == before.locations, "Mastery transaction preserves item ownership")
		var chosen := game.snapshot()
		var disk := FileAccess.get_file_as_bytes(path)
		check(not game.allocate_passive(mastery,65020,game.revision(),path).ok and game.snapshot() == chosen and FileAccess.get_file_as_bytes(path) == disk, "Repeated mastery allocation cannot double conversion or spend points")
		var reopened := Game.new()
		check(reopened.load_build(path) and reopened.snapshot() == chosen and reopened.get_stats() == game.get_stats() and reopened.save_attempts == 0, "Actual44 selected mastery survives native reopen without migration")
		check(game.refund_passive(mastery,game.revision(),path).ok and game.talent_points == points and var_to_bytes(game.get_stats()) == var_to_bytes(stats) and var_to_bytes(game.get_combat_snapshot()) == var_to_bytes(snapshot), "Refund restores exact preselection stats, snapshot and point count")
	# Both eligible original notable groups are connected, so only the shared
	# effect-uniqueness rule can reject the second entrance.
	var ids := route(parents,"29049")
	for id: String in route(parents,"24324"):
		if not ids.has(id): ids.append(id)
	var game := Game.new()
	game._accept_memory(candidate(ids))
	var path := "user://unique-effect44.json"
	check(game.save_build(path) == OK and game.available_passives().has("11505") and game.available_passives().has("63268"), "Two distinct original Fire notable groups are legally available")
	check(game.allocate_passive("11505",65020,game.revision(),path).ok, "First Fire entrance selects shared unique65020")
	var before := game.snapshot()
	var disk := FileAccess.get_file_as_bytes(path)
	var attempts := game.save_attempts
	check(not game.allocate_passive("63268",65020,game.revision(),path).ok and game.snapshot() == before and game.save_attempts == attempts and FileAccess.get_file_as_bytes(path) == disk, "Second eligible entrance rejects duplicate effect before disk write or point spend")
	var duplicate := before.duplicate(true)
	duplicate.talents.allocated.append("63268")
	duplicate.talents.masteries["63268"] = 65020
	duplicate.talents.normal_points -= 1
	check(not Rules.reason(duplicate).is_empty(), "Native envelope also rejects duplicate effect across entrances")
	check(game.refund_passive("11505",game.revision(),path).ok and game.allocate_passive("63268",65020,game.revision(),path).ok and is_equal_approx(game.get_stats().physical_to_fire_conversion,0.4), "Refund releases uniqueness so another eligible entrance can choose40%")


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v069-migration-") or not OS.get_user_data_dir().begins_with(isolation+"/"): quit(78); return
	parser_checks()
	source_closure()
	transaction_checks()
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V069_CONVERSION_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify(evidence,"\t",true,true)+"\n")
		file.close()
	print("Physical-to-fire source: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
