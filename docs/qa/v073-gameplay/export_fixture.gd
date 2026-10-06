extends SceneTree
## Post-pass read-only export of the genuine owned-build file from gameplay.
const Model = preload("res://scripts/canonical_game_state.gd")
const Compiler = preload("res://scripts/combat/skill_compiler.gd")
func _initialize() -> void:
	var source := OS.get_environment("FROST_LOCK_EXPORT_SOURCE")
	var destination := OS.get_environment("FROST_LOCK_EXPORT_DESTINATION")
	if source.is_empty() or destination.is_empty(): quit(78); return
	var model := Model.new()
	if not model.load_build(source): push_error("Actual gameplay fixture failed reload"); quit(1); return
	var raw := model.snapshot()
	if not Model.Rules.reason(raw).is_empty(): push_error("Gameplay fixture invalid"); quit(1); return
	var selected := model.get_skill_cast("frost")
	if not selected.get("ok", false) or not selected.has("freeze_profile"): push_error("Owned freeze cast missing"); quit(1); return
	var expected := {"stats":model.get_stats(),"basic":model.get_basic_cast(),"frost":selected,"plain_frost":Compiler.compile_group("frost", model.get_combat_snapshot(), [])}
	var file := FileAccess.open(destination + "/selected.json", FileAccess.WRITE)
	if file == null: quit(1); return
	file.store_string(JSON.stringify(raw, "\t", true, true)); file.close()
	file = FileAccess.open(destination + "/selected-casts.json", FileAccess.WRITE)
	if file == null: quit(1); return
	file.store_string(JSON.stringify(expected, "\t", true, true)); file.close()
	print("FROST_LOCK_FIXTURE_EXPORT schema=", raw.version, " group=", selected.group_id, " checks=4 failures=0")
	quit(0)
