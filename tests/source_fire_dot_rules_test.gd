extends SceneTree
## Exact source vocabulary, frozen31 coverage and real allocation/refund paths.
const Patterns = preload("res://scripts/passives/source_stat_patterns.gd")
const SourceTree = preload("res://scripts/passives/source_tree_runtime.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Game = preload("res://scripts/canonical_game_state.gd")
const EXPECTED := {"4713":0.04,"5916":0.06,"13559":0.05,"31462":0.05,"54396":0.04,"2550":0.10,"11924":0.10,"29049":0.12}
const FIXTURES := "res://docs/qa/v053-source/fixtures/"
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
	check(SourceTree.CURRENT_SAVE_VERSION == 32 and SourceTree._execution_policy(31) == 25 and SourceTree._execution_policy(32) == 32, "Separate old25 and new32 policy keys")
	for amount: String in ["0","4","5","6","10","12","12.5"]:
		var line := "+" + amount + "% to Fire Damage over Time Multiplier"
		var effect := Patterns.parse_line(line)
		check(effect.supported and effect.grants.size() == 1 and effect.grants[0].stat == "fire_dot_multiplier_add" and effect.grants[0].mode == "flat" and is_equal_approx(effect.grants[0].value,float(amount)*0.01), "Exact percentage becomes fraction: " + amount)
		for version: int in range(14,32):
			check(not SourceTree.line_effect(line,version).supported, "Old%d vocabulary rejects Fire DoT" % version)
		check(SourceTree.line_effect(line,32).supported and not SourceTree.line_effect(line,31).supported, "Interleaved cache policies remain separate")
	for value: Variant in [null,{},[],true,4,NAN,INF,"+NaN% to Fire Damage over Time Multiplier","+INF% to Fire Damage over Time Multiplier","-4% to Fire Damage over Time Multiplier","4% to Fire Damage over Time Multiplier","+4% to Damage over Time Multiplier","+4% to Fire Damage over Time Multiplier with Attack Skills","+4% to Fire Damage over Time Multiplier while Burning","+4% to Fire Damage over Time Multiplier."," +4% to Fire Damage over Time Multiplier","+4% to Fire Damage over Time Multiplier\n","+" + "9".repeat(400) + "% to Fire Damage over Time Multiplier"]:
		var effect := Patterns.parse_line(value)
		check(not effect.supported and effect.grants.is_empty(), "Unknown/scoped/nonfinite/typed input rejected: " + str(value).left(85))


func test_full_nodes() -> void:
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "v31-vocabulary-oracle.json"))
	var gained: Array[String] = []
	var changed_old: Array[String] = []
	for id: String in SourceTree.Data.standard_ids():
		var node := SourceTree.Data.node(id)
		if node.type == "mastery":
			for effect: Dictionary in node.mastery_effects:
				var choice := int(effect.effect)
				var key := id + ":" + str(choice)
				var old := SourceTree.node_effect(id,choice,31)
				var current := SourceTree.node_effect(id,choice,32)
				check((old.status == "full") == oracle.full_masteries.has(key), "Frozen released31 mastery gate " + key)
				if old.status == "full":
					check(old.grants == oracle.full_masteries[key] and current.grants == old.grants and current.status == "full", "Legal old mastery gains no effects: " + key)
				else: check(current.status != "full", "No unapproved mastery opens: " + key)
			continue
		var old := SourceTree.node_effect(id,0,31)
		var current := SourceTree.node_effect(id,0,32)
		check((old.status == "full") == oracle.full_nodes.has(id), "Frozen released31 ordinary gate " + id)
		if old.status == "full":
			if current.grants != old.grants or current.status != "full": changed_old.append(id)
			check(old.grants == oracle.full_nodes[id], "Released old grant identity " + id)
		elif current.status == "full": gained.append(id)
		if EXPECTED.has(id):
			check(current.status == "full" and old.status != "full", "Whole node only opens at32: " + id)
			var amount := 0.0
			for grant: Dictionary in current.grants:
				if grant.stat == "fire_dot_multiplier_add": amount += float(grant.value)
			check(is_equal_approx(amount,EXPECTED[id]), "Original source amount preserved: " + id)
	var expected := EXPECTED.keys()
	expected.sort()
	gained.sort()
	check(gained == expected and changed_old.is_empty(), "Exactly eight newly full nodes; no legal old node gains effects")
	check(SourceTree.node_effect("2550").grants.has({"stat":"life_regen_percent","value":0.012,"mode":"flat"}), "Arsonist retains 1.2% Life regeneration")
	check(SourceTree.node_effect("11924").grants.has({"stat":"fire_increased","value":0.3,"mode":"increased"}), "Breath of Flames retains30% Fire Damage")
	check(SourceTree.node_effect("29049").grants.has({"stat":"fire_resistance","value":0.24,"mode":"flat"}), "Holy Fire retains24% Fire Resistance")
	for id: String in ["7187","22133","36736","50562","53072"]:
		check(SourceTree.node_effect(id).status != "full", "Attack-scoped node retains full-effect gate: " + id)


func test_paths() -> void:
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/qa/v040/source-leech-coverage.json"))
	var report := {"old_schema":31,"new_schema":32,"source_version":"3.29.1","source_sha256":SourceTree.Data.SOURCE_SHA256,"new_full_nodes":EXPECTED,"classes":[],"older_legal_allocations_gaining_effects":[],"newly_reachable_existing_node":"1550"}
	for class_id: int in range(7):
		var old := reachable(class_id,31)
		var current := reachable(class_id,32)
		check(old.size()-1 == int(previous.classes[class_id].all_reachable_non_start_ordinary_count) and old.size()-1 == 676, "Released coverage baseline unchanged for class%d" % class_id)
		check(current.size()-1 == 685 and current.has("1550") and not old.has("1550"), "Eight new full nodes also unlock existing1550; class%d" % class_id)
		var paths := {}
		for id: String in EXPECTED:
			check(current.has(id) and not old.has(id), "Every class reaches new node only under32: " + id)
			paths[id] = current[id]
		report.classes.append({"class_id":class_id,"old_reachable_count":old.size()-1,"new_reachable_count":current.size()-1,"paths_to_new_nodes":paths})
	# Exercise actual persisted game commands over the three complete branches.
	for scenario: Dictionary in [{"class_id":1,"target":"2550","total":0.14},{"class_id":3,"target":"11924","total":0.20},{"class_id":5,"target":"29049","total":0.22}]:
		var game := Game.new()
		var path: String = "user://branch-" + scenario.target + ".json"
		var initial := game.snapshot()
		initial.progress.level = 119
		initial.progress.xp = 0
		initial.talents.normal_points = 123
		game._accept_memory(initial)
		check(game.save_build(path) == OK, "Create isolated branch profile")
		check(game.select_class(scenario.class_id,game.revision(),path).ok, "Actual class selection")
		var route: Array = reachable(scenario.class_id,32)[scenario.target]
		var before_new := 0.0
		for index: int in range(1,route.size()):
			var id: String = route[index]
			check(game.available_passives().has(id), "UI availability exposes next complete node: " + id)
			var before := game.snapshot()
			check(game.allocate_passive(id,0,game.revision(),path).ok and game.revision() == before.revision+1, "Actual save-first allocation: " + id)
			check(Rules.reason(game.snapshot()).is_empty(), "Allocated candidate stays legal")
			if EXPECTED.has(id):
				before_new += EXPECTED[id]
				check(is_equal_approx(game.get_stats().fire_dot_multiplier_add,before_new), "Fraction sum after allocation")
		check(is_equal_approx(game.get_stats().fire_dot_multiplier_add,scenario.total), "Whole branch additive total")
		var allocated := game.snapshot()
		var old := allocated.duplicate(true)
		old.version = 31
		check(not Rules.reason_v31(old).is_empty() and Rules.decode_v31(JSON.parse_string(JSON.stringify(old))).is_empty(), "Exact otherwise-valid allocated route rejected as old31")
		var reopened := Game.new()
		check(reopened.load_build(path) and reopened.snapshot() == allocated and is_equal_approx(reopened.get_stats().fire_dot_multiplier_add,scenario.total), "Actual current32 allocation survives reopen")
		var before_save := FileAccess.get_file_as_bytes(path)
		var bad_revision: Variant = NAN
		check(not game.allocate_passive(scenario.target,0,bad_revision,path).ok and game.snapshot() == allocated and FileAccess.get_file_as_bytes(path) == before_save, "Typed command rejects NaN revision without writes")
		check(game.refund_passive(scenario.target,game.revision(),path).ok and is_equal_approx(game.get_stats().fire_dot_multiplier_add,scenario.total-EXPECTED[scenario.target]), "Actual refund removes exactly the selected grant")
		check(game.allocate_passive(scenario.target,0,game.revision(),path).ok and is_equal_approx(game.get_stats().fire_dot_multiplier_add,scenario.total), "Reallocation restores exact additive total")
	var output := OS.get_environment("V053_SOURCE_REPORT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  ",true,true)+"\n")


func _initialize() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if not xdg.begins_with("/tmp/godot-m1-v053-") or not OS.get_user_data_dir().begins_with(xdg + "/"):
		quit(78)
		return
	test_parser()
	test_full_nodes()
	test_paths()
	print("Source Fire DoT rules: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
