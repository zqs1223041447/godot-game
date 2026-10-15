extends SceneTree
## Visible F6 combat action, including retry of an already partially applied build.
class Fault extends "res://scripts/canonical_game_state.gd":
	var writes := 0
	var fail_at := -1
	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		writes += 1
		return ERR_CANT_CREATE if writes == fail_at else super._write_bytes(path, bytes)
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func check_complete(model):
	var group = model.group_for_key(KEY_1)
	check(not group.is_empty() and model.skill_group(group).skill_id == "tornado", "key 1 casts tornado")
	for id in ["prism_bow", "return_mantle", "detonation_charm"]:
		check(id in model.equipped_items().values(), "equipped " + id)
	var effects = model.get_combat_snapshot().effects
	check("return_on_range" in effects and "explode_on_flight_end" in effects, "return and explosion effects present")
func disk_matches(arena, model):
	var disk = Fault.new()
	check(disk.load_build(arena.build_save_path) and disk.snapshot() == model.snapshot(), "persisted snapshot equals live build")
func run():
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/") or FileAccess.file_exists("user://build_save.json"):
		printerr("Requires a fresh isolated /tmp XDG_DATA_HOME")
		quit(78)
		return
	var fail_step = int(OS.get_environment("TORNADO_FAIL"))
	var unbound = OS.get_environment("TORNADO_UNBOUND") == "1"
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
	if unbound: check(model.unbind_group("group_000001", model.revision(), arena.build_save_path).ok, "supported unbound fixture")
	arena.hud.open_panel("combat")
	var button = arena.hud.find_child("EquipTornadoExample", true, false)
	check(button != null and button.is_visible_in_tree(), "visible connected action")
	var before = model.snapshot()
	var writes = model.writes
	if fail_step > 0: model.fail_at = writes + fail_step
	button.pressed.emit()
	if fail_step > 0:
		check(model.writes - writes == fail_step, "stops at failed persistence boundary")
		check(arena.hud._panel_footer.text.begins_with("龙卷组合未完成"), "truthful incomplete feedback")
		check(not "关闭后按 1 释放" in arena.hud._panel_footer.text, "no false key/effect success claim")
		check(not arena.hud._panel_footer.text.contains("寿命结束爆炸"), "no false explosion claim")
		if fail_step == 1: check(model.snapshot() == before, "failed atomic skill setup is fully unchanged")
	else:
		check(model.writes - writes == 4, "one skill transaction plus three equipment transactions")
		check(arena.hud._panel_footer.text.begins_with("已装配龙卷组合"), "complete feedback after success")
	disk_matches(arena, model)
	model.fail_at = -1
	button.pressed.emit()
	check_complete(model)
	check(arena.hud._panel_footer.text.begins_with("已装配龙卷组合"), "retry reports success only once complete")
	disk_matches(arena, model)
	writes = model.writes
	before = model.snapshot()
	button.pressed.emit()
	check(model.writes == writes and model.snapshot() == before, "completed example retry is no-op")
	check(arena.hud._panel_footer.text.begins_with("已装配龙卷组合"), "no-op is not misreported as failure")
	print("TORNADO_RESULT unbound=", unbound, " fail=", fail_step, " checks=", checks, " failures=", failures)
	arena.queue_free()
	await process_frame
	quit(1 if failures else 0)
