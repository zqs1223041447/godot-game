extends SceneTree
## Actual pause Help surface; isolated saves, logical layout (not native visual QA).
const Model = preload("res://scripts/canonical_game_state.gd")
const SAVE := "user://build_save.json"
const TEST_SAVE := "user://town_test_build_save.json"
var arena: Node
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func settle() -> void:
	for unused: int in range(5): await process_frame
func disk(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
func texts(node: Node) -> String:
	var result := str(node.text) + "\n" if node is Label else ""
	for child: Node in node.get_children(): result += texts(child)
	return result
func verify_help(label: String, capacity: int) -> void:
	arena.set_process(false); arena.hud.set_process(false)
	var model: RefCounted = arena.state
	var before: Dictionary = model.snapshot()
	var saved := disk(SAVE)
	var test_saved := disk(TEST_SAVE)
	var run_revision: int = arena.run_revision
	var world_revision: int = arena.world_context().revision
	for resolution: Vector2i in [Vector2i(1280,720), Vector2i(2560,1440)]:
		for scale: float in [1.0,1.2]:
			root.size = resolution
			arena.visual_settings.font_scale = scale
			arena.visual_settings.ui_scale = 1.1 if scale > 1.0 else 1.0
			arena.hud._apply_presentation()
			arena.hud.open_panel("pause")
			await settle()
			var hud: Node = arena.hud
			var content := texts(hud._panel_body)
			expect(content.contains("当前可用 %d 行主动技能" % capacity), label + ": authoritative active capacity")
			expect(content.contains("按技能行绑定键释放（K 可改键）") and not content.contains("1 – 5：释放技能"), label + ": custom binding instruction")
			expect(content.contains("Alt + 1 – 5：使用药剂"), label + ": distinct flask modifier")
			expect(content.contains("本轮每 20 次有效原始怪击杀可获得随机珠宝") and content.contains("击败原始首领另可获得寻枝晶玉"), label + ": per-run root jewel reward, not persistent gem milestone")
			expect(not content.contains("五个主动技能"), label + ": no stale five-skill limit")
			var footer: Label = hud._panel_footer
			expect(footer.text.contains("保存构筑与正式旅程进度") and footer.text.contains("重开重置本轮战斗") and footer.text.contains("正式地图重试按当前地图入场费重新扣费"), label + ": persisted journey and scoped retry fee")
			var viewport: Rect2 = hud._root.get_viewport_rect()
			expect(viewport.encloses(hud._modal.get_global_rect()) and viewport.encloses(footer.get_global_rect()), label + ": modal/footer fit logical viewport")
			var guide: Control = hud._panel_body.find_child("ControlsGuide",true,false)
			expect(guide.get_global_rect().end.x <= hud._panel_scroll.get_global_rect().end.x + 1.0, label + ": control card fits scroll width")
			expect(hud._panel_scroll.get_h_scroll_bar().max_value <= hud._panel_scroll.size.x + 1.0, label + ": no horizontal content clipping")
			hud.close_panel()
	expect(model.snapshot() == before and disk(SAVE) == saved and disk(TEST_SAVE) == test_saved, label + ": Help never mutates canonical revision/state or either save")
	expect(arena.run_revision == run_revision and arena.world_context().revision == world_revision, label + ": Help never restarts or changes world")
func run() -> void:
	if OS.get_name() != "Linux" or not OS.get_data_dir().begins_with("/tmp/godot-"):
		push_error("Current Help test requires isolated Linux XDG storage")
		quit(78); return
	root.size = Vector2i(1280,720)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false); arena.hud.set_process(false)
	var model: RefCounted = arena.state
	expect(model.save_build(SAVE) == OK, "Isolated canonical fixture persisted")
	expect(model.bind_group("group_000002",KEY_F1,model.revision(),SAVE).ok, "Actual canonical custom F1 binding")
	expect(model.group_for_key(KEY_F1) == "group_000002" and model.group_for_key(KEY_2).is_empty(), "Custom key replaces default numeric binding")
	expect(arena.world_context().normal_town, "Actual formal town mode")
	await verify_help("formal town",10)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91414
	var row_item := ""
	for unused: int in range(8):
		var uid: String = model.award_equipment(rng,30,"rare","nine_slot")
		if not uid.is_empty() and model.item_definition(uid).stats.has("additional_skill_slots"):
			row_item = uid; break
	expect(not row_item.is_empty(), "Real catalog extra-row equipment generated")
	if not row_item.is_empty():
		expect(model.move_item(row_item,{"kind":"equipment","slot_id":model.item_definition(row_item).category},model.revision(),SAVE).ok, "Equip real additional-row item")
	expect(model.active_group_capacity() == 11, "Equipment raises canonical capacity to eleven")
	await verify_help("expanded formal town",11)
	expect(arena.leave_normal_town(arena.world_context().revision).ok, "Enter actual arena practice")
	expect(arena.world_context().mode == "normal", "Practice context verified")
	await verify_help("practice",11)
	expect(arena.enter_town_test(arena.world_context().revision).ok, "Enter actual separate test profile")
	expect(arena.world_context().test_mode and arena.state.group_for_key(KEY_F1) == "group_000002", "Test profile retains custom binding")
	await verify_help("test town",11)
	# Only the Help state adapter is legacy; Main retains its canonical world API.
	var canonical_state: RefCounted = arena.hud._state
	var legacy := preload("res://scripts/build_state.gd").new()
	var legacy_before: Dictionary = legacy._snapshot()
	var legacy_disk := disk(SAVE)
	arena.hud._state = legacy
	arena.hud.open_panel("pause"); await settle()
	var legacy_text := texts(arena.hud._panel_body)
	expect(legacy_text.contains("装备、天赋、珠宝与主动技能行可以自由组合") and not legacy_text.contains("当前可用"), "Legacy fixture gets generic rows, never an invented count")
	expect(legacy._snapshot() == legacy_before and disk(SAVE) == legacy_disk, "Legacy Help preserves state and canonical save")
	arena.hud._state = canonical_state
	arena.free(); await process_frame
	print("Current Help contract: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
