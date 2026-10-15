extends SceneTree
## Exercise the actual F6 panel action, not a direct call to the notification.
class Fault extends "res://scripts/canonical_game_state.gd":
	var writes := 0
	var fail_at := -1
	var failed_uid := ""
	var label_mode := "catalog"
	var protected_bytes := PackedByteArray()
	var protected_snapshot := {}
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		writes += 1
		if writes == fail_at:
			protected_bytes = FileAccess.get_file_as_bytes(path)
			protected_snapshot = snapshot()
			return ERR_CANT_CREATE
		return super._write_bytes(path, bytes)
	func item_definition(uid: String) -> Dictionary:
		# Only corrupt presentation after the failed transaction; fixture must not
		# change equipment validation or the earlier successful transactions.
		if writes == fail_at and uid == failed_uid:
			match label_mode:
				"missing": return {}
				"blank": return {"name": " \t "}
				"null": return {"name": null}
		return super.item_definition(uid)

const IDS := ["prism_bow", "return_mantle", "detonation_charm"]
const LABELS := ["棱光长弓", "归航披风", "终焰护符"]
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func run():
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/") or FileAccess.file_exists("user://build_save.json"):
		printerr("Requires a fresh isolated /tmp XDG_DATA_HOME")
		quit(78)
		return
	var stage := int(OS.get_environment("TORNADO_LABEL_STAGE"))
	var mode := OS.get_environment("TORNADO_LABEL_MODE")
	if stage < 0 or stage >= IDS.size() or mode not in ["catalog", "missing", "blank", "null"]:
		printerr("Requires TORNADO_LABEL_STAGE=0..2 and TORNADO_LABEL_MODE=catalog|missing|blank|null")
		quit(78)
		return
	var arena = load("res://scenes/main.tscn").instantiate()
	var model = Fault.new()
	arena.state = model
	root.add_child(arena)
	arena.set_process(false)
	arena.set_physics_process(false)
	arena.hud.set_process(false)
	arena.auto_fire = false
	await process_frame
	for unused in range(4): arena.hud.close_panel()
	check(arena.save_build(), "initial save")
	check(model.item_definition(IDS[stage]).get("name") == LABELS[stage], "authoritative localized fixture")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F6
	key.pressed = true
	arena._unhandled_key_input(key)
	check(arena.hud.is_blocking() and arena.hud._active_panel == "combat", "real F6 opens combat panel")
	var button = arena.hud.find_child("EquipTornadoExample", true, false)
	check(button != null and button.is_visible_in_tree(), "visible connected trial action")
	if button == null:
		quit(1)
		return
	var writes: int = model.writes
	model.fail_at = writes + stage + 2 # Skill transaction, then selected equipment.
	model.failed_uid = IDS[stage]
	model.label_mode = mode
	button.pressed.emit()
	var footer: String = arena.hud._panel_footer.text
	var expected: String = LABELS[stage] if mode == "catalog" else "所需装备"
	check(footer == "龙卷组合未完成：装备 %s 失败；已完成的设置已保留，请检查存档或装备位置后重试" % expected, "localized truthful partial feedback")
	for id in IDS: check(not footer.contains(id), "no raw item ID: " + id)
	check(not footer.contains("已装配") and not footer.contains("关闭后按 1 释放") and not footer.contains("寿命结束爆炸"), "no complete/effect/key success claim")
	check(model.writes == model.fail_at, "stops on selected equipment failure")
	check(FileAccess.get_file_as_bytes(arena.build_save_path) == model.protected_bytes, "failed persistence preserves exact previous bytes")
	check(model.snapshot() == model.protected_snapshot, "failed persistence preserves previous live build")
	for index in range(IDS.size()):
		check((IDS[index] in model.equipped_items().values()) == (index < stage), "only earlier equipment stages retained")
	var disk = Fault.new()
	check(disk.load_build(arena.build_save_path) and disk.snapshot() == model.snapshot(), "partial persisted build equals live build")
	model.fail_at = -1
	button.pressed.emit()
	check(arena.hud._panel_footer.text.begins_with("已装配龙卷组合"), "retry retains success feedback")
	for id in IDS: check(id in model.equipped_items().values(), "retry completes " + id)
	check(disk.load_build(arena.build_save_path) and disk.snapshot() == model.snapshot(), "retry persisted build equals live build")
	print("TORNADO_LABEL_RESULT stage=", stage, " mode=", mode, " checks=", checks, " failures=", failures)
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
