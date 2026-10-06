extends SceneTree
const Art = preload("res://scripts/visuals/fantasy_actors.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var enemy := {"template_id":"mist_skitter","name":"雾羽掠行体"}
	var before := var_to_bytes(enemy)
	expect(Art.enemy_label(enemy,"普通") == "雾羽掠行体 · 高闪避·较脆", "Trait visible on ordinary mist enemy")
	expect(Art.enemy_label({"template_id":"skitter","name":"掠行体"},"普通") == "掠行体 · 普通", "Other enemy labels unchanged")
	expect(var_to_bytes(enemy) == before, "Visual label read only")
	var shapes := Art.mist_feather_shapes(16.0)
	expect(shapes.size() == 2, "Two bounded static feather accents")
	var inside := true
	for shape: PackedVector2Array in shapes:
		for point: Vector2 in shape:
			if point.length() > 18.0: inside = false
	expect(inside, "Marks stay near existing silhouette")
	expect(Art.mist_feather_shapes(0).is_empty() and Art.mist_feather_shapes(INF).is_empty(), "Invalid radius rejected")
	print("Mist skitter visuals: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
