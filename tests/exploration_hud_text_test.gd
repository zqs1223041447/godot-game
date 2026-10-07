extends SceneTree
const Hud = preload("res://scripts/game_hud.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var context := {"encounter_mode":"exploration","mode":"map","map_name":"银杏回廊","ordinary_kills":0,"ordinary_target":36,"boss_phase":"active"}
	var before := var_to_bytes(context)
	var text := Hud.exploration_progress_text(context)
	expect(text.contains("0 / 36") and text.contains("寻找敌人"), "Exploration progress, no wave label")
	expect(text.contains("首领驻守") and not text.contains("出现"), "Boss exists from entry")
	expect(var_to_bytes(context) == before, "Presentation does not mutate run")
	context.boss_phase = "defeated"
	text = Hud.exploration_progress_text(context)
	expect(text.contains("首领已击败") and text.contains("继续清理"), "Early boss kill is not completion")
	context.mode = "map_complete"
	expect(Hud.exploration_progress_text(context).contains("地图已清理"), "Authoritative completed mode")
	expect(Hud.world_caption(context) == "银杏回廊", "Map title retained")
	expect(Hud.world_caption({"mode":"town","test_mode":false}) == "正式城镇", "Town title retained")
	print("Exploration HUD: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
