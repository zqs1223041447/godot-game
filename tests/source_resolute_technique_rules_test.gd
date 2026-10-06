extends SceneTree
## Whole-entry parsing, frozen37 graph oracle and one real source allocation route.
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const ENTRY := "Your hits can't be Evaded\nNever deal Critical Strikes"
const GRANTS := [{"stat":"resolute_technique", "value":1.0, "mode":"flat"}]
const ROUTE := ["47175", "31628", "9511", "23881", "26523", "6446", "10221", "50422", "50570", "29353", "63282", "31961"]
const ROOT := "res://docs/qa/v061-source/"
var checks := 0
var failures := 0
var evidence := {"class_paths":[]}


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func parser_checks() -> void:
	check(Rules.VERSION == 38 and Source.CURRENT_SAVE_VERSION == 38 and Source._execution_policy(37) == 36, "Schema38 opens an independent source policy;37 remains36")
	var parsed := Patterns.parse_line(ENTRY)
	check(parsed.supported and parsed.grants == GRANTS, "Only the complete two-effect source entry yields one indivisible flat flag")
	check(not Patterns.parse_line(ENTRY, true, true, true, true, true, true, true, true, true, true, false).supported, "Explicit allow_resolute false rejects the whole entry")
	check(not Patterns.parse_line(ENTRY, false).supported, "An older prerequisite gate cannot accidentally admit the new flag")
	for version: int in range(14, 38):
		check(not Source.line_effect(ENTRY, version).supported and Source.line_effect(ENTRY, 38).grants == GRANTS and not Source.line_effect(ENTRY, version).supported, "Interleaved old/new caches remain isolated for schema%d" % version)
	for bad: Variant in [null, [], {}, true, 1, NAN, INF, "Your hits can't be Evaded", "Never deal Critical Strikes",
		"Your Hits can't be Evaded\nNever deal Critical Strikes", "Your hits can't be evaded\nNever deal Critical Strikes",
		ENTRY.replace("\n", "\r\n"), ENTRY.replace("\n", "\r"), ENTRY + "\n", ENTRY + ".", " " + ENTRY, ENTRY + " ",
		ENTRY.replace("\n", " "), ENTRY.replace("\n", "\n\n"), "Never deal Critical Strikes\nYour hits can't be Evaded",
		"Hits can't be Evaded\nNever deal Critical Strikes", "Your hits cannot be Evaded\nNever deal Critical Strikes",
		ENTRY + " while on Full Life", "Hits can't be Evaded against Taunted Enemies", "Taunted Enemies cannot Evade your Attacks",
		"Targets affected by Maim you inflict cannot deal Critical Strikes", "Cannot Evade enemy Attacks\nCannot be Stunned",
		"40% more Attack Damage if Accuracy Rating is higher than Maximum Life\nNever deal Critical Strikes",
		"+10 to Strength\n+10 to Dexterity"]:
		var result := Patterns.parse_line(bad)
		check(not result.supported and result.grants.is_empty(), "Near-match, standalone, conditional, hostile, self-defense and arbitrary multiline forms stay rejected: " + str(bad).left(100))
	var detached := Source.line_effect(ENTRY)
	detached.grants[0].value = 999.0
	check(Source.line_effect(ENTRY).grants == GRANTS, "Caller mutation cannot corrupt the exact-entry cache")


func graph_checks() -> void:
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "fixtures/v37-vocabulary-oracle.json"))
	var opened: Array[String] = []
	var mastery_count := 0
	for id: String in Source.Data.standard_ids():
		var node := Source.Data.node(id)
		var old := Source.node_effect(id, 0, 37)
		var fresh := Source.node_effect(id, 0, 38)
		check((old.status == "full") == oracle.full_nodes.has(id), "Independent frozen v060 node classification: " + id)
		if old.status == "full":
			check(old.grants == oracle.full_nodes[id] and old == fresh, "Every previously legal full node retains identical effects: " + id)
		elif fresh.status == "full": opened.append(id)
		for option: Dictionary in node.mastery_effects:
			var choice := int(option.effect)
			var key := id + ":" + str(choice)
			var prior := Source.node_effect(id, choice, 37)
			check((prior.status == "full") == oracle.full_masteries.has(key) and prior == Source.node_effect(id, choice, 38), "No mastery is newly opened: " + key)
			if prior.status == "full": check(prior.grants == oracle.full_masteries[key], "Frozen mastery effects unchanged: " + key)
			mastery_count += 1
	check(opened == ["31961"], "Exactly one newly full standard node")
	var node := Source.Data.node("31961")
	check(node.name == "Resolute Technique" and node.type == "keystone" and node.stats == [ENTRY] and Source.node_effect("31961").grants == GRANTS, "Raw31961 name, identity and single exact multiline entry stay intact")
	check(Localization.node_name("31961") == "坚决技艺" and Localization.line_status(ENTRY).implemented and Localization.line_status(ENTRY).missing_consumers.is_empty(), "Existing translation becomes supported only with real named consumers")
	check(Localization.display_line(ENTRY) == "你的击中无法被闪避\n不会造成暴击", "Both Chinese effects lose the unimplemented suffix together")
	for row: Dictionary in Localization.STAT_CONSUMER_GROUPS.resolute_technique.code_checks:
		check(FileAccess.get_file_as_string("res://" + row.path).contains(row.contains), "Consumer manifest matches actual executable code: " + row.path)
	for id: String in ["63620", "40907", "35448", "64963", "23407"]:
		var effect := Source.node_effect(id)
		check(effect.status != "full" and not effect.unsupported.is_empty(), "Related but different keystones and hostile/self effects remain blocked: " + id)
		for line: String in effect.unsupported:
			check(Localization.display_line(line).ends_with(Localization.NOT_IMPLEMENTED), "Unsupported source text keeps its dynamic marker")
	evidence.newly_full = opened
	evidence.mastery_options_compared = mastery_count


func paths(class_id: int, version: int) -> Dictionary:
	var start := Source.Data.start_for_class(class_id)
	var result := {start:[start]}
	var queue: Array[String] = [start]
	var offset := 0
	while offset < queue.size():
		var id := queue[offset]
		offset += 1
		for next: String in Source.Data.adjacency(id):
			var node := Source.Data.node(next)
			if result.has(next) or node.type in ["mastery", "start"] or node.source.get("isProxy", false) or node.source.get("isBlighted", false): continue
			if Source.node_effect(next, 0, version).status != "full": continue
			result[next] = result[id] + [next]
			queue.append(next)
	return result


func path_checks() -> void:
	var expected := [15,11,23,18,15,11,25]
	for class_id: int in range(7):
		var prior := paths(class_id, 37)
		var fresh := paths(class_id, 38)
		check(not prior.has("31961") and fresh.has("31961") and fresh["31961"].size()-1 == expected[class_id], "All classes can reach31961 at the verified minimum point count")
		check(fresh.size() == prior.size()+1, "Opening the one keystone admits no further ordinary nodes")
		evidence.class_paths.append({"class_id":class_id, "name":Source.Data.class_definition(class_id).name, "points":expected[class_id], "minimum_level":maxi(1,expected[class_id]-4), "path":fresh["31961"]})
	for index: int in range(1, ROUTE.size()):
		check(Source.Data.adjacency(ROUTE[index-1]).has(ROUTE[index]) and (index == ROUTE.size()-1 or Source.node_effect(ROUTE[index], 0, 37).status == "full"), "Fixed Marauder witness uses existing full adjacent nodes")


func failed_transaction(game: RefCounted, path: String, refund: bool, events: Array) -> void:
	var before: Dictionary = game.snapshot()
	var stats: Dictionary = game.get_stats()
	var bytes := FileAccess.get_file_as_bytes(path)
	var event_count: int = events[0]
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Inject real atomic save failure")
	var result: Dictionary = game.refund_passive("31961",game.revision(),path) if refund else game.allocate_passive("31961",0,game.revision(),path)
	check(not result.ok and game.snapshot() == before and game.get_stats() == stats and FileAccess.get_file_as_bytes(path) == bytes and game._disk_bytes == bytes and events[0] == event_count, "Failed allocate/refund preserves points, grants, revision, events and disk receipt")
	check(DirAccess.remove_absolute(path + ".tmp") == OK, "Remove isolated write failure")


func transaction_checks() -> void:
	var game := Game.new()
	var initial := game.snapshot()
	initial.progress = {"level":7,"xp":0}
	initial.talents.class_id = 1
	initial.talents.allocated = [ROUTE[0]]
	initial.talents.normal_points = 11
	game._accept_memory(initial)
	var path := "user://actual-resolute-route.json"
	check(Rules.reason(initial).is_empty() and game.save_build(path) == OK and game.get_stats().resolute_technique == 0.0, "Level7 Marauder starts with exactly11 points and no flag")
	var events := [0]
	game.changed.connect(func(): events[0] += 1)
	for index: int in range(1, ROUTE.size()):
		var id: String = ROUTE[index]
		check(game.available_passives().has(id), "Real availability admits ordered route: " + id)
		if id == "31961": failed_transaction(game,path,false,events)
		var revision := game.revision()
		check(game.allocate_passive(id,0,revision,path).ok and game.revision() == revision+1 and game.snapshot().talents.normal_points == 11-index and events[0] == index, "One real allocation commits one point, revision and event")
		check(game.get_stats().resolute_technique == (1.0 if id == "31961" else 0.0), "Only the final indivisible node activates both hit-policy effects")
	var allocated := game.snapshot()
	var before := FileAccess.get_file_as_bytes(path)
	check(allocated.talents.allocated == ROUTE and allocated.talents.normal_points == 0 and Rules.reason(allocated).is_empty(), "Actual11-point route is completely legal")
	var old := allocated.duplicate(true)
	old.version = 37
	var permissive := func(_value: Dictionary) -> String: return ""
	check(not Rules.reason_v37(old,permissive).is_empty() and Rules.decode_v37(old).is_empty(), "Otherwise legal allocated route cannot enter frozen37 even with permissive callback")
	check(not game.refund_passive("63282",game.revision(),path).ok and game.snapshot() == allocated and FileAccess.get_file_as_bytes(path) == before, "Disconnecting keystone branch cannot be refunded")
	var reopened := Game.new()
	check(reopened.load_build(path) and reopened.snapshot() == allocated and reopened.get_stats() == game.get_stats() and reopened.save_attempts == 0, "Allocated schema38 reloads without migration or duplicate flag")
	failed_transaction(game,path,true,events)
	check(game.refund_passive("31961",game.revision(),path).ok and game.get_stats().resolute_technique == 0.0 and game.snapshot().talents.normal_points == 1 and events[0] == 12, "Real refund removes the indivisible flag and returns exactly one point")
	check(game.allocate_passive("31961",0,game.revision(),path).ok and game.get_stats().resolute_technique == 1.0 and events[0] == 13, "Reallocation restores exactly one flag")
	for index: int in range(ROUTE.size()-1, 0, -1):
		check(game.refund_passive(ROUTE[index],game.revision(),path).ok, "Actual reverse-order refund restores route")
	check(game.snapshot().talents == initial.talents and game.get_stats().resolute_technique == 0.0 and events[0] == 24, "All12 committed allocations and12 refunds balance points and events")
	var final_reload := Game.new()
	check(final_reload.load_build(path) and final_reload.snapshot() == game.snapshot() and final_reload.get_stats().resolute_technique == 0.0, "Fully refunded state survives reopen")
	evidence.actual_allocations = 12
	evidence.actual_refunds = 12
	evidence.minimum_level = 7


func _initialize() -> void:
	var isolation := OS.get_environment("XDG_DATA_HOME")
	if not isolation.begins_with("/tmp/godot-m1-v061-source-") or not OS.get_user_data_dir().begins_with(isolation + "/"):
		quit(78)
		return
	parser_checks()
	graph_checks()
	path_checks()
	transaction_checks()
	evidence.checks = checks
	evidence.failures = failures
	var output := OS.get_environment("V061_SOURCE_RULES_REPORT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t",true,true)+"\n")
	print("Resolute source rules: %d checks, %d failures;12 actual allocations/12 refunds" % [checks,failures])
	quit(1 if failures else 0)
