extends SceneTree
## One implemented source node with blocked ordinary neighbors; no allocation writes.
const Game = preload("res://scripts/canonical_game_state.gd")
const Source = preload("res://scripts/passives/source_tree_runtime.gd")
const Locale = preload("res://scripts/passives/source_tree_localization.gd")
const PassivePanel = preload("res://scripts/ui/canonical_passive_panel.gd")
const TARGET := "18670"
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-attack-elemental-unreachable-"): quit(78); return
	root.size = Vector2i(1280,720)
	var game := Game.new()
	var before: Dictionary = game.snapshot()
	var writes_before := game.save_attempts
	check(before.version == 55 and before.talents.normal_points > 0,"Current fixture has points; blocked reason is not lack of points")
	var neighbors: Array = Source.Data.adjacency(TARGET).duplicate()
	neighbors.sort()
	check(neighbors == ["15842","37504"],"Only two original ordinary neighbors")
	for id: String in neighbors: check(Source.node_effect(id).status != "full","Original adjacent effect remains unsupported: "+id)
	check(Source.node_effect(TARGET).status == "full" and not game.available_passives().has(TARGET),"Effect supported; ordinary availability remains blocked")
	var panel := PassivePanel.new()
	panel.size = Vector2(1280,720)
	root.add_child(panel)
	panel.setup(game)
	panel._node_clicked(TARGET,MOUSE_BUTTON_LEFT,false)
	panel._node_hovered(TARGET,Rect2())
	await process_frame
	var preview: Dictionary = game.passive_action_preview(TARGET).allocate
	check(not preview.allowed and preview.reason == "断连天赋不在任何普通连通珠宝孔的有效范围内","Authority rejects only the disconnected allocation")
	check(panel._allocate.disabled and panel._allocate.tooltip_text == preview.reason,"Actual allocation button disabled with authoritative reason")
	check(panel._detail.text.contains("当前节点或所选专精的全部效果均已接入游戏") and panel._detail.text.contains("攻击技能造成的元素伤害提高12%") and not panel._detail.text.contains(Locale.NOT_IMPLEMENTED),"Details identify the supported effect accurately")
	check(panel._detail.text.contains("无法分配："+str(preview.reason)),"Details also explain why this implemented node cannot be allocated")
	check(panel._tree._nodes[TARGET].status == "implemented" and not panel._tree._available.has(TARGET),"Canvas separates implementation status from available-node highlight")
	check(panel._tree.tooltip_text.contains("攻击技能造成的元素伤害提高12%"),"Existing hover describes the supported effect")
	panel._allocate_selected()
	check(game.snapshot() == before and game.save_attempts == writes_before,"Disabled allocation action leaves points, build and disk untouched")
	panel.queue_free()
	await process_frame
	print("ATTACK_ELEMENTAL_UNREACHABLE_UI checks=%d failures=%d" % [checks,failures.size()])
	quit(1 if not failures.is_empty() else 0)
