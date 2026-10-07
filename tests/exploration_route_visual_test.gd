extends SceneTree
const EnvironmentArt = preload("res://scripts/visuals/fantasy_environment.gd")
const Hud = preload("res://scripts/game_hud.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	for end: Vector2 in [Vector2(480,0),Vector2(0,480),Vector2(480,480)]:
		var segments := [{"from":Vector2.ZERO,"to":end,"width":72.0}]
		var original := var_to_bytes(segments)
		var stones := EnvironmentArt.route_stones(segments)
		expect(not stones.is_empty(), "Path receives paving")
		var direction := end.normalized()
		for stone: PackedVector2Array in stones:
			for point: Vector2 in stone:
				expect(absf(direction.cross(point)) <= 36.01, "All stone vertices inside verified route width")
				expect(direction.dot(point) >= -0.01 and direction.dot(point) <= end.length()+0.01, "Paving stays inside route endpoints")
		expect(var_to_bytes(segments) == original, "Route drawing does not mutate layout")
	expect(EnvironmentArt.route_stones([]).is_empty(), "Old geometry without routes unchanged")
	expect(EnvironmentArt.route_stones([{"from":Vector2(INF,0),"to":Vector2.ZERO}]).is_empty(), "Malformed geometry not drawn")
	var context := {"mode":"map","map_name":"银杏回廊","ordinary_kills":4,"ordinary_target":36,"boss_phase":"resident","outpost_states":[{"state":"cleared"},{"state":"resident"},{"state":"active"},{"state":"resident"},{"state":"resident"},{"state":"resident"}]}
	var text := Hud.exploration_progress_text(context)
	expect(text.contains("驻点 1/6") and text.contains("首领驻守"), "Outpost progress and boss independent")
	context.boss_phase = "defeated"
	expect(Hud.exploration_progress_text(context).contains("继续清理"), "Boss first still requires remaining clears")
	print("Exploration route visuals: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
