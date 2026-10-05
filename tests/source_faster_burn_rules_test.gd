extends SceneTree
## Exact source vocabulary, frozen32 coverage and real allocation/refund paths.
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const EXPECTED := {"11364":0.05,"43684":0.05,"59766":0.15}
const FIXTURES := "res://docs/qa/v054-source/fixtures/"
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func reachable(class_id: int, version: int) -> Dictionary:
	var start := SourceTree.Data.start_for_class(class_id)
	var paths := {start:[start]}
	var queue: Array[String] = [start]
	var offset := 0
	while offset < queue.size():
		var current: String = queue[offset]
		offset += 1
		for id: String in SourceTree.Data.adjacency(current):
			var node := SourceTree.Data.node(id)
			if paths.has(id) or node.type in ["mastery","start"] or node.source.get("isProxy",false) or node.source.get("isBlighted",false): continue
			if SourceTree.node_effect(id,0,version).status != "full": continue
			paths[id] = paths[current] + [id]
			queue.append(id)
	return paths


func test_parser() -> void:
	check(SourceTree.CURRENT_SAVE_VERSION == 33 and SourceTree._execution_policy(31) == 25 and SourceTree._execution_policy(32) == 32 and SourceTree._execution_policy(33) == 33, "Distinct frozen25, frozen32 and current33 policies")
	for amount: String in ["0","5","10","15","12.5"]:
		var line := "Damaging Ailments deal damage " + amount + "% faster"
		var effect := Patterns.parse_line(line)
		check(effect.supported and effect.grants.size() == 1 and effect.grants[0].stat == "damaging_ailments_faster" and effect.grants[0].mode == "flat" and is_equal_approx(effect.grants[0].value,float(amount)*0.01), "Exact percentage becomes additive fraction: " + amount)
		for version: int in range(14,33):
			check(not SourceTree.line_effect(line,version).supported, "Old%d vocabulary rejects faster ailments" % version)
		check(SourceTree.line_effect(line,33).supported and not SourceTree.line_effect(line,32).supported, "Interleaved cache policies remain separate")
	for value: Variant in [null,{},[],true,4,NAN,INF,"Damaging Ailments deal damage NaN% faster","Damaging Ailments deal damage INF% faster","Damaging Ailments deal damage -5% faster","Damaging Ailments deal damage +5% faster","Ignites deal Damage 5% faster","5% increased Damage with Ailments","Damaging Ailments deal damage 5% faster with Bow Skills","Damaging Ailments deal damage 5% faster while Burning","Damaging Ailments deal damage 5% faster."," Damaging Ailments deal damage 5% faster","Damaging Ailments deal damage 5% faster\n","Damaging Ailments deal damage " + "9".repeat(400) + "% faster"]:
		var effect := Patterns.parse_line(value)
		check(not effect.supported and effect.grants.is_empty(), "Unknown/scoped/nonfinite/typed input rejected: " + str(value).left(85))


func test_full_nodes() -> void:
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v32-vocabulary-oracle.json"))
	var gained: Array[String] = []
	var changed_old: Array[String] = []
	for id: String in SourceTree.Data.standard_ids():
		var node := SourceTree.Data.node(id)
		if node.type == "mastery":
			for effect: Dictionary in node.mastery_effects:
				var choice := int(effect.effect)
				var key := id + ":" + str(choice)
				var old := SourceTree.node_effect(id,choice,32)
				var current := SourceTree.node_effect(id,choice,33)
				check((old.status == "full") == oracle.full_masteries.has(key), "Frozen released32 mastery gate " + key)
				if old.status == "full":
					check(old.grants == oracle.full_masteries[key] and current.grants == old.grants and current.status == "full", "Legal old mastery gains no effects: " + key)
				else: check(current.status != "full", "No unapproved mastery opens: " + key)
			continue
		var old := SourceTree.node_effect(id,0,32)
		var current := SourceTree.node_effect(id,0,33)
		check((old.status == "full") == oracle.full_nodes.has(id), "Frozen released32 ordinary gate " + id)
		if old.status == "full":
			if current.grants != old.grants or current.status != "full": changed_old.append(id)
			check(old.grants == oracle.full_nodes[id], "Released old grant identity " + id)
		elif current.status == "full": gained.append(id)
		if EXPECTED.has(id):
			check(current.status == "full" and old.status != "full", "Whole node only opens at33: " + id)
			var amount := 0.0
			for grant: Dictionary in current.grants:
				if grant.stat == "damaging_ailments_faster": amount += float(grant.value)
			check(is_equal_approx(amount,EXPECTED[id]), "Original source amount preserved: " + id)
	var expected := EXPECTED.keys()
	expected.sort()
	gained.sort()
	check(gained == expected and changed_old.is_empty(), "Exactly three newly full nodes; no legal old node gains effects")
	var matching_standard: Array[String] = []
	var matching_nonstandard: Array[String] = []
	var mastery_occurrences := 0
	for id: String in SourceTree.Data.nodes():
		var node := SourceTree.Data.node(id)
		for line: String in node.stats:
			var effect := SourceTree.line_effect(line)
			if effect.grants.any(func(grant: Dictionary) -> bool: return grant.stat == "damaging_ailments_faster"):
				if SourceTree.Data.standard_ids().has(id): matching_standard.append(id)
				else: matching_nonstandard.append(id)
		for mastery: Dictionary in node.mastery_effects:
			for line: String in mastery.stats:
				var effect := SourceTree.line_effect(line)
				if effect.grants.any(func(grant: Dictionary) -> bool: return grant.stat == "damaging_ailments_faster"): mastery_occurrences += 1
	matching_standard.sort()
	check(matching_standard == ["11364","43684","48823","59766"] and matching_nonstandard == ["19686"] and mastery_occurrences == 0, "Exact pinned-source occurrence audit: four standard, one nonstandard, no mastery")
	check(SourceTree.node_effect("48823").status == "partial" and SourceTree.node_effect("48823").unsupported == ["30% increased Damage Over Time with Bow Skills"], "Deadly Draw remains blocked by unsupported Bow DoT")
	check(SourceTree.node_effect("19686").status == "partial" and SourceTree.node_effect("19686").unsupported == ["20% increased Damage with Ailments"], "Nonstandard Wasting Affliction remains parser-only and partial")


func test_paths() -> void:
	var report := {"old_schema":32,"new_schema":33,"source_version":"3.29.1","source_sha256":SourceTree.Data.SOURCE_SHA256,"new_full_nodes":EXPECTED,"classes":[],"older_legal_allocations_gaining_effects":[],"parser_only_standard_nodes":["48823"],"parser_only_nonstandard_nodes":["19686"],"mastery_occurrences":0}
	for class_id: int in range(7):
		var old := reachable(class_id,32)
		var current := reachable(class_id,33)
		check(old.size()-1 == 685, "Released coverage baseline unchanged for class%d" % class_id)
		check(current.size()-1 == 688, "Exactly three new reachable ordinary nodes; class%d" % class_id)
		var paths := {}
		for id: String in EXPECTED:
			check(current.has(id) and not old.has(id), "Every class reaches new node only under33: " + id)
			paths[id] = current[id]
		report.classes.append({"class_id":class_id,"old_reachable_count":old.size()-1,"new_reachable_count":current.size()-1,"paths_to_new_nodes":paths})
	# Exercise actual persisted commands along the complete Faster Ailments branch.
	for scenario: Dictionary in [{"class_id":4,"target":"59766","total":0.25}]:
		var game := Game.new()
		var path: String = "user://branch-" + scenario.target + ".json"
		var initial := game.snapshot()
		initial.progress.level = 119
		initial.progress.xp = 0
		initial.talents.normal_points = 123
		game._accept_memory(initial)
		check(game.save_build(path) == OK, "Create isolated branch profile")
		check(game.select_class(scenario.class_id,game.revision(),path).ok, "Actual class selection")
		var route: Array = reachable(scenario.class_id,33)[scenario.target]
		var before_new := 0.0
		for index: int in range(1,route.size()):
			var id: String = route[index]
			check(game.available_passives().has(id), "UI availability exposes next complete node: " + id)
			var before := game.snapshot()
			check(game.allocate_passive(id,0,game.revision(),path).ok and game.revision() == before.revision+1, "Actual save-first allocation: " + id)
			check(Rules.reason(game.snapshot()).is_empty(), "Allocated candidate stays legal")
			if EXPECTED.has(id):
				before_new += EXPECTED[id]
				check(is_equal_approx(game.get_stats().damaging_ailments_faster,before_new), "Fraction sum after allocation")
		check(is_equal_approx(game.get_stats().damaging_ailments_faster,scenario.total), "Whole branch additive total")
		var allocated := game.snapshot()
		var old := allocated.duplicate(true)
		old.version = 32
		check(not Rules.reason_v32(old).is_empty() and Rules.decode_v32(JSON.parse_string(JSON.stringify(old))).is_empty(), "Exact otherwise-valid allocated route rejected as old32")
		var reopened := Game.new()
		check(reopened.load_build(path) and reopened.snapshot() == allocated and is_equal_approx(reopened.get_stats().damaging_ailments_faster,scenario.total), "Actual current33 allocation survives reopen")
		check(not game.refund_passive("43684",game.revision(),path).ok and game.snapshot() == allocated, "Whole-graph gate rejects disconnecting allocated Dirty Techniques")
		var before_save := FileAccess.get_file_as_bytes(path)
		var bad_revision: Variant = NAN
		check(not game.allocate_passive(scenario.target,0,bad_revision,path).ok and game.snapshot() == allocated and FileAccess.get_file_as_bytes(path) == before_save, "Typed command rejects NaN revision without writes")
		check(game.refund_passive(scenario.target,game.revision(),path).ok and is_equal_approx(game.get_stats().damaging_ailments_faster,scenario.total-EXPECTED[scenario.target]), "Actual refund removes exactly the selected grant")
		check(game.allocate_passive(scenario.target,0,game.revision(),path).ok and is_equal_approx(game.get_stats().damaging_ailments_faster,scenario.total), "Reallocation restores exact additive total")
	var output := OS.get_environment("V054_SOURCE_REPORT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  ",true,true)+"\n")


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-v054-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	test_parser()
	test_full_nodes()
	test_paths()
	print("Source faster damaging ailments rules: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
