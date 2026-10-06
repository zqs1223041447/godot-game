extends SceneTree
## v080: nine resource wording corrections through the existing real panel.
## Source grants/topology stay intact; no arena, allocation, combat or schema edit.
const Game = preload("res://scripts/canonical_game_state.gd")
const PassivePanel = preload("res://scripts/ui/canonical_passive_panel.gd")
const Data = preload("res://scripts/passives/source_tree_data.gd")
const Runtime = preload("res://scripts/passives/source_tree_runtime.gd")
const Localization = preload("res://scripts/passives/source_tree_localization.gd")
const SAVE_PATH := "user://v080-passive-resource-wording.json"
const ISOLATION_ROOT := "/tmp/godot-m1-v080-wording"
const SOURCE_FILE_SHA256 := "9774a8ec1fe16199e775fe99a20853837ca8c7725c48dfcd9d6ee69646ff934f"
const TARGETS := {
	"25714": {"en": "Mana and Increased Mana Cost", "zh": "魔力与提高魔力消耗", "grants": [
		{"stat": "max_mana", "mode": "increased", "value": 0.10},
		{"stat": "mana_cost_increased", "mode": "increased", "value": 0.05}]},
	"26960": {"en": "Forethought", "zh": "深谋", "grants": [
		{"stat": "max_mana", "mode": "increased", "value": 0.30},
		{"stat": "mana_cost_increased", "mode": "increased", "value": 0.10}]},
	"10835": {"en": "Dreamer", "zh": "梦行者", "grants": [
		{"stat": "mana_regen_increased", "mode": "increased", "value": 0.30},
		{"stat": "mana_cost_efficiency_increased", "mode": "increased", "value": 0.15}]},
	"31033": {"en": "Robust", "zh": "强韧", "grants": [
		{"stat": "life_regen", "mode": "flat", "value": 10.0},
		{"stat": "life_regen_percent", "mode": "flat", "value": 0.012}]},
	"22356": {"en": "Hematophagy", "zh": "嗜血", "grants": [
		{"stat": "life_leech_max_rate_increased", "mode": "increased", "value": 0.40},
		{"stat": "life_leech_rate_increased", "mode": "increased", "value": 1.0}]},
	"65053": {"en": "Essence Sap", "zh": "精华树液", "grants": [
		{"stat": "attack_mana_leech", "mode": "flat", "value": 0.005},
		{"stat": "mana_leech_max_rate_increased", "mode": "increased", "value": 0.50},
		{"stat": "mana_leech_rate_increased", "mode": "increased", "value": 1.0}]},
	"39530": {"en": "Vitality Void", "zh": "活力虚空", "grants": [
		{"stat": "attack_life_leech", "mode": "flat", "value": 0.01},
		{"stat": "life_leech_max_rate_increased", "mode": "increased", "value": 0.40}]},
}
const WORDING := [
	{"en": "5% increased Mana Cost of Skills", "zh": "技能的魔力消耗提高5%", "refs": [["25714", 1]]},
	{"en": "10% increased Mana Cost of Skills", "zh": "技能的魔力消耗提高10%", "refs": [["26960", 1]]},
	{"en": "30% increased Mana Regeneration Rate", "zh": "魔力再生速率提高30%", "refs": [["10835", 0]]},
	{"en": "Regenerate 10 Life per second", "zh": "每秒再生10点生命", "refs": [["31033", 0]]},
	{"en": "Regenerate 1.2% of Life per second", "zh": "每秒再生相当于最大生命1.2%的生命", "refs": [["31033", 1]]},
	{"en": "100% increased total Recovery per second from Life Leech", "zh": "生命偷取的每秒总回复速率提高100%", "refs": [["22356", 1]]},
	{"en": "100% increased total Recovery per second from Mana Leech", "zh": "魔力偷取的每秒总回复速率提高100%", "refs": [["65053", 2]]},
	{"en": "40% increased Maximum total Life Recovery per second from Leech", "zh": "生命偷取的每秒总回复上限提高40%", "refs": [["22356", 0], ["39530", 1]]},
	{"en": "50% increased Maximum total Mana Recovery per second from Leech", "zh": "魔力偷取的每秒总回复上限提高50%", "refs": [["65053", 1]]},
]
var game: RefCounted
var panel: Control
var checks := 0
var failures := 0
var changed_count := 0
var finished := false
var source_before := PackedByteArray()
var source_sha_before := ""
var observations: Array[Dictionary] = []
var wording_observations: Array[Dictionary] = []
var grants_before := {}
var graph_before := PackedByteArray()
var canvas_before := PackedByteArray()


func _initialize() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if OS.get_name() != "Linux" or not isolated.begins_with(ISOLATION_ROOT + "/") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		push_error("Refusing non-isolated userdata: use /tmp/godot-m1-v080-wording/<run>/data")
		quit(78)
		return
	create_timer(30.0).timeout.connect(func() -> void:
		if not finished:
			check(false, "Resource-wording fixture exceeded its 30-second guard")
			finish()
	)
	call_deferred("run")


func run() -> void:
	if not check(Data.ready() and Localization.ready(), "Original tree and Chinese display map load"):
		finish()
		return
	source_before = var_to_bytes(Data.nodes())
	source_sha_before = FileAccess.get_sha256(Data.PATH)
	check(source_sha_before == SOURCE_FILE_SHA256, "Source file matches the unchanged v079 baseline SHA256")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Data.PATH))
	graph_before = var_to_bytes(source_graph())
	check(Data.standard_ids() == raw.standard_tree.default_allocation_graph.node_ids, "All standard graph IDs match pinned source")
	for id: String in TARGETS:
		var node: Dictionary = Data.node(id)
		var position: Dictionary = raw.positions[id]
		check(node.id == id and node.name == TARGETS[id].en and node.name == raw.nodes[id].name, "Original ID and English name: " + id)
		check(node.position == Vector2(float(position.x), float(position.y)), "Original source coordinate: " + id)
		check(Localization.node_name(id) == TARGETS[id].zh, "Existing Chinese node name remains unchanged: " + id)
		check(node.source == raw.nodes[id] and Data.adjacency(id) == raw.standard_tree.default_allocation_graph.adjacency[id], "Complete raw node and graph links remain intact: " + id)
		check(Data.standard_ids().has(id) and node.has_position and not node.source.get("isProxy", false) and not node.source.get("isBlighted", false), "Complete node remains in allocatable standard graph: " + id)
		var effect: Dictionary = Runtime.node_effect(id)
		check(effect.status == "full" and effect.unsupported.is_empty() and effect.supported == node.stats, "All original source lines remain fully supported: " + id)
		check(effect.grants == TARGETS[id].grants, "Complete node retains all exact typed grants and values: " + id)
		for grant: Dictionary in effect.grants:
			check(grant.stat is String and grant.mode is String and grant.value is float, "Grant scalar and identity types remain unchanged: " + id + " " + grant.stat)
		grants_before[id] = var_to_bytes(effect)
	for row: Dictionary in WORDING:
		check(Localization.source_effect_line(row.en) == row.zh and Localization.display_line(row.en) == row.zh, "Exact target wording has no missing/unimplemented suffix: " + row.en)
		var line_status: Dictionary = Localization.line_status(row.en)
		check(line_status.implemented and line_status.parser_supported and line_status.missing_consumers.is_empty(), "Target wording keeps its implemented status: " + row.en)
		for ref: Array in row.refs:
			var entry: Dictionary = Data.stat_entry(ref[0], ref[1])
			check(entry.node_id == ref[0] and entry.stat_index == ref[1] and entry.raw_line == row.en and entry.node_name == TARGETS[ref[0]].en, "Exact source node ID/stat index/English line retained: " + str(ref))
			check(entry.source_hash == raw.source.data_sha256 and entry.source_commit == raw.source.commit and entry.source_version == raw.source.version, "Exact line provenance retained: " + str(ref))
			check(Runtime.line_effect(row.en).grants == [TARGETS[ref[0]].grants[ref[1]]] and line_status.grants == Runtime.line_effect(row.en).grants, "Exact typed grant is independent of translated text: " + str(ref))
		wording_observations.append({"source_line": row.en, "display_line": Localization.display_line(row.en), "references": row.refs, "typed_grants": line_status.grants})
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
	canvas_before = var_to_bytes({"nodes": panel._tree._nodes, "edges": panel._tree._edges})
	check(panel._tree._edges == expected_edges(raw), "Actual canvas retains all original standard graph edges")
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
			check(panel._detail.text.begins_with(TARGETS[id].zh + "\n" + id + "\n"), "Search details retain existing node name and original ID: " + query)
			assert_readonly(before, "query " + query)
			observations.append({"query": query, "selected_id": panel.selected_node_id, "name": panel._tree._nodes[id].name, "detail_heading": panel._detail.text.split("\n")[0], "position": [Data.node(id).position.x, Data.node(id).position.y]})
	for id: String in TARGETS:
		check(var_to_bytes(Runtime.node_effect(id)) == grants_before[id], "Entire typed node effect unchanged after display/search: " + id)
	check(var_to_bytes(source_graph()) == graph_before, "All original graph IDs, adjacency and class starts remain unchanged")
	check(var_to_bytes({"nodes": panel._tree._nodes, "edges": panel._tree._edges}) == canvas_before, "Search/hover preserve actual canvas topology, coordinates and node metadata")
	check(var_to_bytes(Data.nodes()) == source_before, "All cached source names, IDs, coordinates and stats remain byte-identical")
	check(FileAccess.get_sha256(Data.PATH) == source_sha_before, "Original source file SHA256 unchanged")
	finish()


func check_display(id: String, expected_name: String) -> void:
	if not check(panel._tree._nodes.has(id), "Real canvas contains node: " + id): return
	check(panel._tree._nodes[id].name == expected_name, "Canvas retains existing node name: " + id + " " + expected_name)
	check(panel._tree._nodes[id].id == id and panel._tree._nodes[id].position == Data.node(id).position, "Canvas preserves ID and coordinate: " + id)
	panel._tree.node_clicked.emit(id, MOUSE_BUTTON_LEFT, false)
	panel._tree.node_hovered.emit(id, Rect2())
	check(panel._detail.text.begins_with(expected_name + "\n" + id + "\n"), "Details show display name and original ID: " + id)
	check(panel._detail.text.contains("\n\n" + Localization.display_lines(Data.node(id).stats) + "\n\n"), "Details retain source effect rows and existing status labels: " + id)
	check(panel._tree.tooltip_text.begins_with(expected_name + "\n"), "Actual hover shows display name: " + id)
	check(panel._tree._nodes[id].status == "implemented" and panel._detail.text.contains("当前节点或所选专精的全部效果均已接入游戏"), "Canvas and detail preserve full-node implementation status: " + id)
	for row: Dictionary in WORDING:
		for ref: Array in row.refs:
			if ref[0] != id: continue
			check(panel._tree._nodes[id].description.split("\n").has(row.zh), "Actual canvas description contains exact wording: " + id + " " + row.zh)
			check(panel._detail.text.split("\n").has(row.zh), "Actual details contain exact wording: " + id + " " + row.zh)
			check(panel._tree.tooltip_text.split("\n").has(row.zh), "Actual hover contains exact wording: " + id + " " + row.zh)


func source_graph() -> Dictionary:
	var graph := {"ids": Data.standard_ids(), "starts": Data.class_starts(), "adjacency": {}}
	for id: String in graph.ids:
		graph.adjacency[id] = Data.adjacency(id)
	return graph


func expected_edges(raw: Dictionary) -> Array:
	var edges := []
	for id: String in raw.standard_tree.default_allocation_graph.node_ids:
		for adjacent: String in raw.standard_tree.default_allocation_graph.adjacency[id]:
			if id < adjacent: edges.append({"a": id, "b": adjacent})
	return edges


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
	seed(80031033)
	result.global_draws = [randi(), randi(), randi(), randi()]
	seed(80031033)
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
	print("V080_RESOURCE_WORDING " + JSON.stringify(wording_observations))
	print("V080_PASSIVE_SEARCH " + JSON.stringify(observations))
	print("V080_SOURCE_SHA256 " + source_sha_before)
	print("Passive resource wording: %d checks, %d failures; 9 exact wording keys, 7 complete nodes, 21 real-panel search submissions" % [checks, failures])
	if is_instance_valid(panel): panel.queue_free()
	quit(1 if failures else 0)
