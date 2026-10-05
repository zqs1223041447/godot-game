extends SceneTree
## Focused display/state compatibility; the exhaustive vocabulary audit lives in
## source_tree_localization_test.gd. This fixture never advances arena combat.
const Game = preload("res://scripts/canonical_game_state.gd")
const Rules = preload("res://scripts/save/canonical_build_rules.gd")
const Data = preload("res://scripts/passives/source_tree_data.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const SAVE_PATH := "user://v057-localization-compatibility.json"
const FULL_NODES := ["11364", "43684", "59766", "4713", "5916", "13559", "31462", "54396", "2550", "11924", "29049"]
const CLASS_ID := 4
var checks := 0
var failures := 0
var finished := false
var arena: Node
var game: RefCounted
var panel: Control
var template: Dictionary = {}
var routes: Dictionary = {}
var raw: Dictionary = {}
var source_before := PackedByteArray()
var source_file_before := PackedByteArray()
var changed_count := 0
var readonly_phases: Array[String] = []


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if OS.get_name() != "Linux" or not isolated.begins_with("/tmp/godot-m1-v057-compat.") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		push_error("Refusing non-isolated userdata; use the v057 compatibility runner")
		quit(78)
		return
	# A failed assertion/script in an awaited flow must not leave an idle process.
	create_timer(45.0).timeout.connect(func() -> void:
		if not finished:
			check(false, "Compatibility fixture exceeded its 45-second guard")
			finish()
	)
	call_deferred("run")


func run() -> void:
	if not check(Data.ready() and Localization.ready(), "Source and display mapping load"):
		finish()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Data.PATH))
	if not check(parsed is Dictionary, "Raw source fixture is readable"):
		finish()
		return
	raw = parsed
	source_before = var_to_bytes(Data.nodes())
	source_file_before = FileAccess.get_file_as_bytes(Data.PATH)
	routes = reachable_routes(CLASS_ID)
	if not check(routes.has("59766") and routes.has("29049"), "Both actual build branches have legal routes"):
		finish()
		return
	game = Game.new()
	template = game.snapshot()
	var allocated: Array = routes["59766"].duplicate()
	for id: String in routes["29049"]:
		if not allocated.has(id): allocated.append(id)
	if not install_allocation(allocated):
		finish()
		return
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://scenes/main.tscn")
	if not check(scene != null, "Real arena scene loads"):
		finish()
		return
	arena = scene.instantiate()
	arena.state = game
	arena.build_save_path = SAVE_PATH
	arena.set_process(false)
	arena.set_physics_process(false)
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	await frames()
	if not check(arena.state == game and game is Game, "HUD uses the real canonical model and isolated save"):
		finish()
		return
	arena.rng.seed = 570057
	arena.critical_runtime.reset(570057)
	game.changed.connect(func() -> void: changed_count += 1)
	check(float(game.get_stats().damaging_ailments_faster) > 0.0 and float(game.get_stats().fire_dot_multiplier_add) > 0.0,
		"Browsing fixture starts with actually allocated faster and Fire DoT stats")
	var before := readonly_checkpoint()
	arena.hud.open_panel("talents")
	await frames()
	panel = arena.hud._passive_panel
	if not check(is_instance_valid(panel) and panel.model == game, "T opens the canonical localized passive panel"):
		finish()
		return
	check_graph("standard")
	assert_readonly(before, "open populated Chinese tree")
	await browse_and_search()
	await browse_partitions()
	await browse_masteries()
	test_detached_status()
	test_full_node_gates()
	test_partial_node_gates()
	before = readonly_checkpoint()
	arena.hud.close_panel()
	await frames()
	arena.hud.open_panel("talents")
	await frames()
	check(arena.hud._passive_panel == panel, "Close/reopen reuses the canonical tree panel")
	check_graph("standard")
	assert_readonly(before, "close and reopen localized tree")
	check(var_to_bytes(Data.nodes()) == source_before, "All cached source IDs, English names/stats, mastery IDs and coordinates stay byte-identical")
	check(FileAccess.get_file_as_bytes(Data.PATH) == source_file_before, "Pinned English source file stays byte-identical")
	finish()


func browse_and_search() -> void:
	var before := readonly_checkpoint()
	for id: String in ["59766", "29049", "48823", "11239"]:
		panel._node_clicked(id, MOUSE_BUTTON_LEFT, false)
		panel._node_hovered(id, Rect2())
		check(panel.selected_node_id == id and panel._tree._selected_id == id, "Single click retains source selection " + id)
		check(panel._detail.text.begins_with(Localization.node_name(id) + "\n" + id + "\n"), "Detail displays Chinese name with original ID " + id)
		check(panel._tree.tooltip_text.begins_with(Localization.node_name(id)), "Hover uses translated name " + id)
		check(Data.node(id).stats == raw.nodes[id].get("stats", []), "Source English stats remain authoritative " + id)
		check_display_rows(id)
	# Wind Dancer has a unique source/localized name; avoid duplicate-name aliases.
	for query: String in [Localization.node_name("11239"), "  WIND DANCER  ", "11239"]:
		panel._search.text = query
		panel._search.text_submitted.emit(query)
		check(panel.selected_node_id == "11239" and panel._tree._selected_id == "11239", "Chinese/English/ID search reaches the same original node: " + query)
		check(panel._tree.pan == -Data.node("11239").position * panel._tree.zoom, "Search centers the original source coordinate")
	var selected: String = panel.selected_node_id
	panel._find_node("  ")
	panel._find_node("v057-no-such-passive-node")
	check(panel.selected_node_id == selected, "Blank and missing searches preserve selection")
	await frames()
	assert_readonly(before, "node details, hover and Chinese/English/ID searches")


func browse_partitions() -> void:
	var before := readonly_checkpoint()
	# Sample one real ascendancy and expansion; the existing audit covers wording
	# for every partition. Assert graph membership so a stale refresh cannot pass.
	for index: int in [1, panel._partition.item_count - 1, 0]:
		var key: String = str(panel._partition.get_item_metadata(index))
		panel._partition.item_selected.emit(index)
		await frames()
		check(panel._subtree == key, "Partition selection retains source key " + key)
		check_graph(key)
		if key != "standard": check(panel._allocate.disabled, "Browse-only partition never allocates " + key)
	panel._focus_start()
	await frames()
	check_graph("standard")
	assert_readonly(before, "ascendancy/expansion browsing and return to main tree")


func browse_masteries() -> void:
	var before := readonly_checkpoint()
	for id: String in ["11505", "10495"]:
		panel._node_clicked(id, MOUSE_BUTTON_LEFT, false)
		var options: Array = Data.node(id).mastery_effects
		if not check(panel._mastery.item_count == options.size(), "Mastery picker retains source option count " + id): continue
		for index: int in range(options.size()):
			var effect_id: int = int(options[index].effect)
			check(int(panel._mastery.get_item_metadata(index)) == effect_id, "Mastery item metadata retains original effect ID")
			check(panel._mastery.is_item_disabled(index) == (Runtime.node_effect(id, effect_id).status != "full"), "Mastery choice gate follows the complete source option")
			check(panel._mastery.get_item_text(index) == Localization.display_lines(options[index].stats, " · "), "Picker has exactly the per-source-line markers")
			panel._mastery.select(index)
			panel._mastery.item_selected.emit(index)
			var selected_effect: int = int(panel._mastery.get_item_metadata(panel._mastery.selected))
			check_display_rows(id, selected_effect)
			check(not game.snapshot().talents.masteries.has(id), "Reading a mastery option never commits it " + id)
	await frames()
	assert_readonly(before, "mastery choice switching and per-line detail labels")


func test_detached_status() -> void:
	var before := readonly_checkpoint()
	var line := "Damaging Ailments deal damage 5% faster"
	var expected := Localization.line_status(line)
	var detached := Localization.line_status(line)
	if check(not detached.grants.is_empty(), "Status fixture has a nested grant"):
		detached.grants[0].stat = "v057-mutated-copy"
		detached.grants[0].value = -999.0
		detached.grants.append({"stat": "injected"})
		detached.missing_consumers.append("injected")
		detached.implemented = false
		check(Localization.line_status(line) == expected, "Status grants, nested grant dictionaries and missing-consumer arrays are detached")
		check(Localization.display_line(line) == Localization.source_effect_line(line), "Mutating a returned status cannot contaminate later UI labels")
	assert_readonly(before, "read-only status-cache copy isolation")


func test_full_node_gates() -> void:
	for id: String in FULL_NODES:
		if not check(routes.has(id), "Full target has a legal connected route " + id): continue
		var allocated: Array = routes[id].duplicate()
		allocated.pop_back()
		if not install_allocation(allocated): return
		var before := readonly_checkpoint()
		panel._node_clicked(id, MOUSE_BUTTON_LEFT, false)
		check(game.available_passives().has(id), "Actual model admits full target with its allocated predecessor " + id)
		check(Runtime.node_effect(id).status == "full" and not panel._allocate.disabled, "Whole-node parser gate and UI allocation agree " + id)
		check(not panel._detail.text.contains(Localization.NOT_IMPLEMENTED), "Full faster/Fire DoT target has no false unsupported row " + id)
		check(panel._tree._nodes[id].status == "implemented", "Canvas agrees with full-node implementation " + id)
		check_display_rows(id)
		assert_readonly(before, "inspect available full node " + id)


func test_partial_node_gates() -> void:
	# Deadly Draw currently has no reachable supported neighbor. Use an already
	# legal build to check its display and refusals; do not invent adjacency.
	var reachable_neighbors := 0
	for neighbor: String in Data.adjacency("48823"):
		if routes.has(neighbor): reachable_neighbors += 1
	print("Deadly Draw fixture: %d supported reachable neighbors; no adjacency-satisfied claim" % reachable_neighbors)
	if install_allocation(routes["59766"]):
		check_partial("48823", 0, 1)
	# A mastery node can be available because a DIFFERENT choice is full. Test
	# the exact disabled effect, without forcing selection or clicking Allocate.
	if install_allocation(routes["29049"]):
		check(Data.node("29049").group_id == Data.node("11505").group_id, "Fire Mastery has its real allocated notable prerequisite")
		check_partial("11505", 36313, 1)


func check_partial(id: String, effect_id: int, marker_count: int) -> void:
	var before := readonly_checkpoint()
	panel._node_clicked(id, MOUSE_BUTTON_LEFT, false)
	check(Runtime.node_effect(id, effect_id).status == "partial", "Mixed source option is still partial " + id)
	if effect_id != 0:
		var index := -1
		for option_index: int in range(panel._mastery.item_count):
			if int(panel._mastery.get_item_metadata(option_index)) == effect_id: index = option_index
		if not check(index >= 0, "Partial mastery effect exists in the actual picker"): return
		var option_text: String = panel._mastery.get_item_text(index)
		var lines: Array = Runtime.lines_for(id, effect_id)
		check(panel._mastery.is_item_disabled(index), "Exact mixed supported/unsupported mastery choice is disabled")
		check(option_text == Localization.display_lines(lines, " · "), "Disabled mastery option preserves its exact complete source rows")
		check(option_text.count(Localization.NOT_IMPLEMENTED) == marker_count, "Only the unsupported row is marked inside the disabled mastery option")
		for line: String in lines:
			var implemented: bool = bool(Localization.line_status(line).implemented)
			check(Localization.display_line(line).count(Localization.NOT_IMPLEMENTED) == (0 if implemented else 1), "Disabled mastery labels classify the source rows independently")
		# The detail panel legitimately shows the current selectable/fallback
		# option. Never assert it displays this disabled entry or allocate it.
		var selected_effect: int = int(panel._mastery.get_item_metadata(panel._mastery.selected))
		check_display_rows(id, selected_effect)
	else:
		check(not game.available_passives().has(id) and panel._allocate.disabled, "Actual availability and UI reject mixed ordinary node " + id)
		check(panel._detail.text.count(Localization.NOT_IMPLEMENTED) == marker_count, "Only the unsupported original row carries a marker " + id)
		check_display_rows(id)
		panel._allocate_selected()
	var rejected: Dictionary = game.allocate_passive(id, effect_id, game.revision(), SAVE_PATH)
	check(not rejected.get("ok", false), "Direct canonical command also refuses exact mixed option " + id)
	assert_readonly(before, "partial UI and command refusal " + id)


func check_display_rows(id: String, effect_id: int = 0) -> void:
	var lines: Array = Runtime.lines_for(id, effect_id)
	check(panel._detail.text.contains("\n\n" + Localization.display_lines(lines) + "\n\n"), "Details preserve one display entry per complete source row " + id)
	for line: String in lines:
		var implemented: bool = bool(Localization.line_status(line).implemented)
		check(Localization.display_line(line).count(Localization.NOT_IMPLEMENTED) == (0 if implemented else 1), "Per-line marker agrees with implemented status " + id)


func reachable_routes(class_id: int) -> Dictionary:
	var start := Data.start_for_class(class_id)
	var found := {start: [start]}
	var queue: Array[String] = [start]
	var offset := 0
	while offset < queue.size():
		var current := queue[offset]
		offset += 1
		for id: String in Data.adjacency(current):
			var node := Data.node(id)
			if found.has(id) or node.type in ["mastery", "start"] or node.source.get("isProxy", false) or node.source.get("isBlighted", false): continue
			if Runtime.node_effect(id).status != "full": continue
			found[id] = found[current] + [id]
			queue.append(id)
	return found


func install_allocation(allocated: Array) -> bool:
	var candidate := template.duplicate(true)
	candidate.revision = game.revision() + 1
	candidate.progress.level = 119
	candidate.progress.xp = 0
	candidate.talents.class_id = CLASS_ID
	candidate.talents.allocated = allocated.duplicate()
	candidate.talents.masteries = {}
	candidate.talents.normal_points = 123 - (allocated.size() - 1)
	var reason: String = Rules.reason(candidate)
	if not check(reason.is_empty(), "Constructed source-path fixture passes full canonical validation: " + reason): return false
	game._accept_memory(candidate)
	if not check(game.save_build(SAVE_PATH) == OK, "Persist legal path fixture in isolated userdata"): return false
	game.changed.emit()
	return true


func readonly_checkpoint() -> Dictionary:
	var result := {
		"model": var_to_bytes(game.snapshot()), "stats": var_to_bytes(game.get_stats()),
		"combat": var_to_bytes(game.get_combat_snapshot()), "revision": game.revision(),
		"epoch": game._content_epoch, "changed": changed_count,
		"save": FileAccess.get_file_as_bytes(SAVE_PATH),
		"save_attempts": game.save_attempts, "successful_saves": game.successful_saves,
		"files": userdata_files(),
		"rng": arena.rng.state, "critical": arena.critical_runtime.checkpoint(),
		"world": [arena.run_revision, arena.health, arena.mana, arena.shield, arena.total_shots, arena.total_damage]
	}
	seed(570000 + readonly_phases.size())
	result.global_draws = [randi(), randi(), randi(), randi()]
	seed(570000 + readonly_phases.size())
	return result


func assert_readonly(before: Dictionary, label: String) -> void:
	check(var_to_bytes(game.snapshot()) == before.model and game.revision() == before.revision, label + ": canonical snapshot/revision unchanged")
	check(var_to_bytes(game.get_stats()) == before.stats and var_to_bytes(game.get_combat_snapshot()) == before.combat, label + ": actual faster/Fire DoT stats and compiled combat snapshot unchanged")
	check(game._content_epoch == before.epoch and changed_count == before.changed, label + ": no model mutation or changed signal")
	check(FileAccess.file_exists(SAVE_PATH) and FileAccess.get_file_as_bytes(SAVE_PATH) == before.save, label + ": persisted original bytes unchanged")
	check(game.save_attempts == before.save_attempts and game.successful_saves == before.successful_saves, label + ": no save attempts or writes")
	check(userdata_files() == before.files, label + ": no added backup/temp files")
	check(arena.rng.state == before.rng and arena.critical_runtime.checkpoint() == before.critical, label + ": real arena and critical RNG unchanged")
	check([arena.run_revision, arena.health, arena.mana, arena.shield, arena.total_shots, arena.total_damage] == before.world, label + ": no world progression")
	check([randi(), randi(), randi(), randi()] == before.global_draws, label + ": global RNG draw sequence unchanged")
	readonly_phases.append(label)


func userdata_files() -> PackedStringArray:
	var files := DirAccess.get_files_at(OS.get_user_data_dir())
	files.sort()
	return files


func check_graph(key: String) -> void:
	var ids: Array = raw.standard_tree.default_allocation_graph.node_ids
	var edge_ids: Array = raw.standard_tree.default_allocation_graph.edge_ids
	if key != "standard":
		var branch: Dictionary = raw.special_subtrees.expansion_jewels if key == "expansion" else raw.special_subtrees.ascendancies.get(key, {})
		ids = branch.get("positioned_node_ids", [])
		edge_ids = branch.get("internal_edge_ids", [])
	var expected_positions := {}
	for id: String in ids:
		var pos: Dictionary = raw.positions[id]
		expected_positions[id] = Vector2(float(pos.x), float(pos.y))
	var actual_positions := {}
	var embedded_ids_match := true
	for id: String in panel._tree._nodes:
		var node: Dictionary = panel._tree._nodes[id]
		actual_positions[id] = node.position
		embedded_ids_match = embedded_ids_match and str(node.id) == id
	check(embedded_ids_match and actual_positions == expected_positions, "Canvas retains exact source node IDs/positions for " + key)
	var wanted := {}
	for id: String in edge_ids: wanted[id] = true
	var expected_edges: Array[String] = []
	for edge: Dictionary in raw.edges:
		if wanted.has(str(edge.id)): expected_edges.append(edge_key(str(edge.a), str(edge.b)))
	var actual_edges: Array[String] = []
	for edge: Dictionary in panel._tree._edges: actual_edges.append(edge_key(str(edge.a), str(edge.b)))
	expected_edges.sort()
	actual_edges.sort()
	check(actual_edges == expected_edges, "Canvas retains exact source edge endpoints for " + key)
	if key == "standard": check(actual_positions.size() == 2387 and actual_edges.size() == 2697, "Standard graph keeps 2387 nodes and 2697 edges")


func edge_key(a: String, b: String) -> String:
	return a + ":" + b if a < b else b + ":" + a


func frames() -> void:
	for unused: int in range(3): await process_frame


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


func finish() -> void:
	if finished: return
	finished = true
	print("Passive localization compatibility: %d checks, %d failures; %d read-only phases" % [checks, failures, readonly_phases.size()])
	if is_instance_valid(arena): arena.queue_free()
	quit(1 if failures else 0)
