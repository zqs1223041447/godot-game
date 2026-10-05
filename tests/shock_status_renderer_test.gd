extends SceneTree
const Art = preload("res://scripts/visuals/shock_status_renderer.gd")
const Foreground = preload("res://scripts/visuals/foreground_arena_layer.gd")
const ArenaArt = preload("res://scripts/visuals/arena_visuals.gd")
var checks := 0
var failures := 0
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var state := {"target_kind":"monster", "target_id":1, "position":Vector2(100,100), "remaining_seconds":2.0}
	var rows := [state]
	var before := var_to_bytes(rows)
	var marks := Art.primitives(rows)
	expect(marks.size() == 1, "One compact mark per actor")
	expect(marks[0].points.size() == 4 and marks[0].width == 1.8, "Bounded lightning polyline")
	expect(var_to_bytes(rows) == before, "Input statuses unchanged")
	expect(Art.primitives([state,state]).size() == 1, "Duplicate target deduplicated")
	var player := state.duplicate(true)
	player.target_kind = "player"
	expect(Art.primitives([state,player]).size() == 2, "Player and monster identity namespaces differ")
	for bad: Variant in [null, {}, "invalid", {"target_kind":"npc"}, {"position":Vector2(INF,0)}]:
		expect(Art.primitives([bad]).is_empty(), "Malformed row ignored")
	for remain: float in [0.0,-1.0,INF,NAN]:
		var invalid := state.duplicate(true)
		invalid.remaining_seconds = remain
		expect(Art.primitives([invalid]).is_empty(), "Expired or nonfinite status hidden")
	var many: Array = []
	for i: int in range(110):
		var row := state.duplicate(true)
		row.target_id = i
		many.append(row)
	expect(Art.primitives(many).size() == 101, "Drawing work bounded without hiding entire oversized set")
	marks[0].points[0] = Vector2.ZERO
	expect(Art.primitives(rows)[0].points[0] != Vector2.ZERO, "Output geometry detached")
	var foreground := Foreground.new()
	expect(foreground.shock_statuses().is_empty(), "Detached foreground safely empty")
	foreground.free()
	expect(ArenaArt.ShockArt == Art, "Both arena paths reference the authoritative renderer")
	print("Shock status renderer: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
