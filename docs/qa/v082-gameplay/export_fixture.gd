extends SceneTree
## Read-only export from a passing actual-Main fixture. No rerolled equipment,
## fresh grants, helper-built approximation, editor import, or gameplay execution.
const Model = preload("res://scripts/canonical_game_state.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
func _initialize() -> void:
	var source := OS.get_environment("COLD_DURATION_EXPORT_SOURCE")
	var destination := OS.get_environment("COLD_DURATION_EXPORT_DESTINATION")
	if source.is_empty() or destination.is_empty(): quit(78); return
	var bytes := FileAccess.get_file_as_bytes(source)
	var model := Model.new()
	if not model.load_build(source) or not Model.Rules.reason(model.snapshot()).is_empty() or not model.pending_items().is_empty(): push_error("Actual Main fixture failed read-only validation"); quit(1); return
	var cast: Dictionary = model.get_skill_cast("frost")
	if not cast.get("ok", false): push_error("Actual owned Frost cast missing"); quit(1); return
	var result := {"stats":model.get_stats(),"cast":cast,"preview":Preview.details(cast)}
	if FileAccess.get_file_as_bytes(source) != bytes: push_error("Fixture read changed source bytes"); quit(1); return
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null: quit(1); return
	file.store_string(JSON.stringify(result, "\t", true, true)); file.close()
	print("COLD_DURATION_READONLY_EXPORT schema=", model.snapshot().version, " group=", cast.group_id, " checks=4 failures=0")
	quit(0)
