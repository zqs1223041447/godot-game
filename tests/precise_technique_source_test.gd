extends SceneTree
## Full original source entry, isolated frozen vocabulary, and actual graph transactions.
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const ENTRY := "40% more Attack Damage if Accuracy Rating is higher than Maximum Life\nNever deal Critical Strikes"
const GRANTS := [{"stat":"precise_technique","value":1.0,"mode":"flat"}]
const ROUTES := {
	"ranger":{"class_id":2,"ids":["50459","39821","52904","444","61306","60942","64709","3469","63620"]},
	"duelist":{"class_id":4,"ids":["50986","39725","63649","49806","6580","19711","20010","23471","3469","63620"]},
}
const ROOT := "res://docs/qa/v070-migration/"
var checks := 0
var failures := 0
var evidence := {"routes":{},"source_effects_compared":0,"opened_nodes":[]}


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	return ok


func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


func parser_checks() -> void:
	check(Source.CURRENT_SAVE_VERSION == 45 and Source.PRECISE_TECHNIQUE_SAVE_VERSION == 45, "Source45 is the first Precise Technique vocabulary")
	check(Source.Data.node("63620").stats == [ENTRY], "Original63620 contains one indivisible exact multiline entry")
	check(Patterns.parse_line(ENTRY).grants == GRANTS, "Whole entry grants only the indivisible flag")
	check(not Patterns.parse_line(ENTRY,true,true,true,true,true,true,true,true,true,true,true,true,true,true,false).supported, "Explicit Precise vocabulary gate closes entry")
	check(not Patterns.parse_line(ENTRY,false).supported, "Earlier prerequisite vocabulary closes entry")
	for version: int in range(14,45):
		check(not Source.line_effect(ENTRY,version).supported and Source.line_effect(ENTRY,45).grants == GRANTS and not Source.line_effect(ENTRY,version).supported, "Interleaved old/current caches remain separate: "+str(version))
	check(Source._execution_policy(40) == 40 and Source._execution_policy(41) == 41 and Source._execution_policy(42) == 41 and Source._execution_policy(43) == 41 and Source._execution_policy(44) == 44, "All earlier source policies remain frozen")
	for bad: Variant in [null,[],{},true,40,NAN,INF,"",ENTRY+"."," "+ENTRY,ENTRY+" ",ENTRY+"\n",ENTRY.replace("\n","\r\n"),ENTRY.replace("40%","50%"),ENTRY.replace("40%","40.0%"),ENTRY.replace("higher than","equal to or higher than"),ENTRY.replace("Attack","Spell"),ENTRY.replace("Maximum Life","Current Life"),ENTRY.replace("Rating","rating"),ENTRY.replace("\n"," "),"40% more Attack Damage if Accuracy Rating is higher than Maximum Life","Never deal Critical Strikes"]:
		var parsed := Patterns.parse_line(bad)
		check(not parsed.supported and parsed.grants.is_empty(), "Malformed or incomplete conditional entry stays closed: "+str(bad))
	var detached := Source.line_effect(ENTRY)
	detached.grants[0].value = 9.0
	check(Source.line_effect(ENTRY).grants == GRANTS, "Caller cannot mutate cached grant")
	check(Localization.line_status(ENTRY).implemented and not Localization.display_line(ENTRY).contains(Localization.NOT_IMPLEMENTED), "Chinese display has actual consumer-backed implementation")
	for item: Dictionary in Localization.STAT_CONSUMER_GROUPS.precise_technique.code_checks:
		check(FileAccess.get_file_as_string("res://"+item.path).contains(item.contains), "Evidence points to actual consumer: "+item.path+":"+item.contains)


func source_closure() -> void:
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"fixtures/v44-oracle.json"))
	var opened: Array[String] = []
	for key: String in oracle.source_effects:
		var parts := key.split(":")
		var id := parts[0]
		var choice := int(parts[1])
		check(digest(var_to_bytes(Source.node_effect(id,choice,44))) == oracle.source_effects[key], "All old44 node/choice effects retain exact native bytes: "+key)
		var current := Source.node_effect(id,choice,45)
		if id == "63620" and choice == 0:
			check(current.status == "full" and current.grants == GRANTS and current.supported == [ENTRY] and current.unsupported.is_empty(), "The full original63620 opens both effects together")
			opened.append(id)
		else: check(digest(var_to_bytes(current)) == oracle.source_effects[key], "Every other source node/choice remains unchanged: "+key)
		evidence.source_effects_compared += 1
	check(opened == ["63620"], "Exactly the original63620 opens")
	evidence.opened_nodes = opened
	for id: String in Source.Data.standard_ids():
		if Source.Data.node(id).name in ["Avatar of Fire", "Elemental Overload"]:
			check(Source.node_effect(id).status != "full", "Other partially implemented keystones stay blocked: "+id)


func transaction_checks() -> void:
	for label: String in ROUTES:
		var ids: Array = ROUTES[label].ids
		var game := Game.new()
		var initial := game.snapshot()
		initial.progress = {"level":ids.size()-5,"xp":0}
		initial.talents.class_id = ROUTES[label].class_id
		initial.talents.allocated = [ids[0]]
		initial.talents.normal_points = ids.size()-1
		game._accept_memory(initial)
		var path := "user://precise45-"+label+".json"
		if not check(game.save_build(path) == OK, "Create legal real allocation fixture: "+label): continue
		var disconnected_bytes := FileAccess.get_file_as_bytes(path)
		var disconnected_attempts := game.save_attempts
		check(not game.allocate_passive("63620",0,game.revision(),path).ok and game.snapshot() == initial and game.save_attempts == disconnected_attempts and FileAccess.get_file_as_bytes(path) == disconnected_bytes, "Cannot skip the original path or spend a disconnected point")
		for id: String in ids.slice(1,-1):
			if not check(game.allocate_passive(id,0,game.revision(),path).ok, "Actual original graph edge allocation: "+label+":"+id): return
		check(game.available_passives().has("63620"), "Full preceding original route exposes63620: "+label)
		var before := game.snapshot()
		var stats := game.get_stats()
		var snapshot := game.get_combat_snapshot()
		var points := game.talent_points
		check(not stats.has("precise_technique") and not snapshot.has("precise_technique"), "Unselected state does not gain optional Precise fields")
		if not check(game.allocate_passive("63620",0,game.revision(),path).ok, "Actual63620 allocation succeeds: "+label): return
		check(game.talent_points == 0 and game.talent_points == points-1 and game.get_stats().get("precise_technique",0.0) == 1.0, "Only one point spent and one flag granted")
		check(game.snapshot().items == before.items and game.snapshot().locations == before.locations, "Allocation never gifts or alters ownership")
		var chosen := game.snapshot()
		var disk := FileAccess.get_file_as_bytes(path)
		var attempts := game.save_attempts
		check(not game.allocate_passive("63620",0,game.revision(),path).ok and game.snapshot() == chosen and game.save_attempts == attempts and FileAccess.get_file_as_bytes(path) == disk, "Duplicate allocation fails before write or point spend")
		var reopened := Game.new()
		check(reopened.load_build(path) and reopened.snapshot() == chosen and reopened.get_stats() == game.get_stats() and reopened.save_attempts == 0, "Current45 native reopen retains selected node without rewriting")
		check(game.refund_passive("63620",game.revision(),path).ok and game.talent_points == points and var_to_bytes(game.get_stats()) == var_to_bytes(stats) and var_to_bytes(game.get_combat_snapshot()) == var_to_bytes(snapshot), "Refund restores exact prior stats, combat snapshot, and points")
		evidence.routes[label] = {"class_id":ROUTES[label].class_id,"ids":ids,"points_spent":ids.size()-1,"minimum_level":ids.size()-5,"real_allocate_save_reopen_refund":true}


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v070-migration-") or not OS.get_user_data_dir().begins_with(isolation+"/"): quit(78); return
	parser_checks()
	source_closure()
	transaction_checks()
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V070_PRECISE_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify(evidence,"\t",true,true)+"\n")
		file.close()
	print("Precise Technique source: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
