extends SceneTree
## v079: exercise the existing canonical panel and its real search signal only.
## No arena, allocation, combat, schema change, or replacement search algorithm.
const Game = preload("res://scripts/canonical_game_state.gd")
const PassivePanel = preload("res://scripts/ui/canonical_passive_panel.gd")
const Data = preload("res://scripts/passives/source_tree_data.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const SAVE_PATH := "user://v079-passive-name-corrections.json"
const ISOLATION_ROOT := "/tmp/godot-m1-v079-search"
const TARGETS := {
	"8833": {"en": "Heart of Ice", "zh": "冰霜之心"},
	"56716": {"en": "Heart of Thunder", "zh": "雷霆之心"},
}
const CONTROLS := {"11239": "风舞者", "29049": "神圣火焰"}
var game: RefCounted
var panel: Control
var checks := 0
var failures := 0
var changed_count := 0
var finished := false
var source_before := PackedByteArray()
var source_sha_before := ""
var observations: Array[Dictionary] = []


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if OS.get_name() != "Linux" or not isolated.begins_with(ISOLATION_ROOT + "/") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		push_error("Refusing non-isolated userdata: use /tmp/godot-m1-v079-search/<run>/data")
		quit(78)
		return
	create_timer(30.0).timeout.connect(func() -> void:
		if not finished:
			check(false, "Name-correction fixture exceeded its 30-second guard")
			finish()
	)
	call_deferred("run")


func run() -> void:
	if not check(Data.ready() and Localization.ready(), "Original tree and Chinese display map load"):
		finish()
		return
	source_before = var_to_bytes(Data.nodes())
	source_sha_before = FileAccess.get_sha256(Data.PATH)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Data.PATH))
	for id: String in TARGETS:
		var node: Dictionary = Data.node(id)
		var position: Dictionary = raw.positions[id]
		check(node.id == id and node.name == TARGETS[id].en and node.name == raw.nodes[id].name, "Original ID and English name: " + id)
		check(node.position == Vector2(float(position.x), float(position.y)), "Original source coordinate: " + id)
		check(Localization.node_name(id) == TARGETS[id].zh, "Correct Chinese display name: " + id)
	game = Game.new()
	if not check(game.save_build(SAVE_PATH) == OK, "Persist real canonical fixture in isolated userdata"):
		finish()
		return
	game.changed.connect(func() -> void: changed_count += 1)
	var before := readonly_checkpoint()
	root.size = Vector2i(1280, 720)
	panel = PassivePanel.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.setup(game, SAVE_PATH)
	await process_frame
	check(panel.model == game and panel.save_path == SAVE_PATH, "Actual CanonicalPassivePanel uses real model and isolated save")
	check(panel._tree._nodes.size() == 2387, "Existing standard graph loads")
	for id: String in TARGETS:
		check_display(id, TARGETS[id].zh)
	for id: String in CONTROLS:
		check_display(id, CONTROLS[id])
	assert_readonly(before, "panel setup, display, details and hover")
	# Alternate targets so a no-op/stale selection cannot pass any search.
	for field: String in ["zh", "en", "id"]:
		for id: String in TARGETS:
			before = readonly_checkpoint()
			check(panel.selected_node_id != id, "Search begins on a different node: " + id)
			var query: String = id if field == "id" else str(TARGETS[id][field])
			panel._search.text = query
			panel._search.text_submitted.emit(query)
			check(panel.selected_node_id == id and panel._tree._selected_id == id, "Actual Chinese/English/ID search selects: " + query)
			check(panel._tree.pan == -Data.node(id).position * panel._tree.zoom, "Search centers original coordinate: " + query)
			check(panel._detail.text.begins_with(TARGETS[id].zh + "\n" + id + "\n"), "Search details retain corrected display name and original ID: " + query)
			assert_readonly(before, "query " + query)
			observations.append({"query": query, "selected_id": panel.selected_node_id, "name": panel._tree._nodes[id].name, "detail_heading": panel._detail.text.split("\n")[0], "position": [Data.node(id).position.x, Data.node(id).position.y]})
	check(var_to_bytes(Data.nodes()) == source_before, "All cached source names, IDs, coordinates and stats remain byte-identical")
	check(FileAccess.get_sha256(Data.PATH) == source_sha_before, "Original source file SHA256 unchanged")
	finish()


func check_display(id: String, expected_name: String) -> void:
	if not check(panel._tree._nodes.has(id), "Real canvas contains node: " + id): return
	check(panel._tree._nodes[id].name == expected_name, "Canvas display name: " + id + " " + expected_name)
	check(panel._tree._nodes[id].id == id and panel._tree._nodes[id].position == Data.node(id).position, "Canvas preserves ID and coordinate: " + id)
	panel._tree.node_clicked.emit(id, MOUSE_BUTTON_LEFT, false)
	panel._tree.node_hovered.emit(id, Rect2())
	check(panel._detail.text.begins_with(expected_name + "\n" + id + "\n"), "Details show display name and original ID: " + id)
	check(panel._detail.text.contains("\n\n" + Localization.display_lines(Data.node(id).stats) + "\n\n"), "Details retain source effect rows and existing status labels: " + id)
	check(panel._tree.tooltip_text.begins_with(expected_name + "\n"), "Actual hover shows display name: " + id)


func readonly_checkpoint() -> Dictionary:
	var files := DirAccess.get_files_at(OS.get_user_data_dir())
	files.sort()
	var result := {
		"model": var_to_bytes(game.snapshot()), "revision": game.revision(),
		"stats": var_to_bytes(game.get_stats()), "combat": var_to_bytes(game.get_combat_snapshot()),
		"epoch": game._content_epoch, "changed": changed_count,
		"save": FileAccess.get_file_as_bytes(SAVE_PATH), "files": files,
		"save_attempts": game.save_attempts, "successful_saves": game.successful_saves,
	}
	# CanonicalGameState/PassivePanel do not own a combat RNG. Check their real
	# accessible global RNG without inventing an unrelated arena or mock RNG.
	seed(7908833)
	result.global_draws = [randi(), randi(), randi(), randi()]
	seed(7908833)
	return result


func assert_readonly(before: Dictionary, label: String) -> void:
	check(var_to_bytes(game.snapshot()) == before.model and game.revision() == before.revision, label + ": snapshot/revision unchanged")
	check(var_to_bytes(game.get_stats()) == before.stats and var_to_bytes(game.get_combat_snapshot()) == before.combat, label + ": stats/combat snapshot unchanged")
	check(game._content_epoch == before.epoch and changed_count == before.changed, label + ": no model mutation or changed signal")
	check(FileAccess.get_file_as_bytes(SAVE_PATH) == before.save, label + ": persisted bytes unchanged")
	check(game.save_attempts == before.save_attempts and game.successful_saves == before.successful_saves, label + ": no save attempts or writes")
	var files := DirAccess.get_files_at(OS.get_user_data_dir())
	files.sort()
	check(files == before.files, label + ": no added backup/temp files")
	check([randi(), randi(), randi(), randi()] == before.global_draws, label + ": global RNG sequence unchanged")


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


func finish() -> void:
	if finished: return
	finished = true
	print("V079_PASSIVE_SEARCH " + JSON.stringify(observations))
	print("V079_SOURCE_SHA256 " + source_sha_before)
	print("Passive name corrections: %d checks, %d failures; 6 real-panel search submissions" % [checks, failures])
	if is_instance_valid(panel): panel.queue_free()
	quit(1 if failures else 0)
