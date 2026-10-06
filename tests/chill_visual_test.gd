extends SceneTree
const Art = preload("res://scripts/visuals/chill_status_renderer.gd")
const Foreground = preload("res://scripts/visuals/foreground_arena_layer.gd")
const ArenaArt = preload("res://scripts/visuals/arena_visuals.gd")
const Maps = preload("res://scripts/world/map_catalog.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var row := {"target_kind":"player","target_id":0,"position":Vector2(50,70),"remaining_seconds":1.2}
	var original := var_to_bytes(row)
	expect(Art.primitives([row]).size() == 3, "Single three-line snowflake")
	expect(Art.primitives([row,row]).size() == 3, "No duplicate markers")
	expect(var_to_bytes(row) == original, "Read-only state")
	var marks := Art.primitives([row])
	marks[0]["from"] = Vector2.ZERO
	expect(Art.primitives([row])[0]["from"] != Vector2.ZERO, "Detached primitives")
	for remaining: float in [0.0, -1.0, INF, NAN]:
		row.remaining_seconds = remaining
		expect(Art.primitives([row]).is_empty(), "Inactive or invalid status hidden")
	row.remaining_seconds = 1.2
	row.target_kind = "monster"
	expect(Art.primitives([row]).is_empty(), "No invented monster status")
	row.target_kind = "player"
	row.position = Vector2(INF,0)
	expect(Art.primitives([row]).is_empty(), "Invalid position hidden")
	var foreground := Foreground.new()
	expect(foreground.chill_statuses().is_empty(), "Detached foreground safe")
	foreground.free()
	expect(ArenaArt.ChillArt == Art, "Shared rendering implementation")
	var description: String = Maps.SPECIAL.frost_patrol.description
	expect(description.contains("25%") and description.contains("1.2秒") and description.contains("不产生冻结"), "Map effect clear")
	print("Chill visual: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
