extends SceneTree
const Art = preload("res://scripts/visuals/freeze_status_renderer.gd")
const Preview = preload("res://scripts/combat/damage_preview.gd")
const Rules = preload("res://scripts/combat/frost_lock_rules.gd")
var checks := 0
var failures := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void:
	var row := {"target_kind":"monster","target_id":1,"position":Vector2(20,30),"remaining_seconds":0.6}
	var before := var_to_bytes(row)
	expect(Art.primitives([row]).size() == 1, "Active freeze marker")
	expect(Art.primitives([row,row]).size() == 1, "Deduplicates target")
	expect(var_to_bytes(row) == before, "Read-only renderer")
	row.remaining_seconds = 0.0
	expect(Art.primitives([row]).is_empty(), "No mark in thaw immunity")
	row.remaining_seconds = 0.6
	row.target_kind = "player"
	expect(Art.primitives([row]).is_empty(), "No invented player freeze")
	row.target_kind = "monster"
	row.position = Vector2(INF,0)
	expect(Art.primitives([row]).is_empty(), "Invalid location hidden")
	var states := []
	for i in range(110): states.append({"target_kind":"monster","target_id":i,"position":Vector2.ZERO,"remaining_seconds":0.1})
	expect(Art.primitives(states).size() == 100, "Bounded status drawing")
	var profile: Dictionary = Rules.PLAYER_POLICY.duplicate(true)
	profile.enabled = true
	var cast := {"ok":true,"freeze_profile":profile}
	var old := var_to_bytes(cast)
	var lines := Preview.freeze_lines(cast)
	expect(lines.size() == 3 and lines[0].contains("0.60") and lines[0].contains("0.35") and lines[0].contains("0.20"), "Three authoritative durations")
	expect(lines[1].contains("1.50") and lines[1].contains("不刷新"), "Shared thaw immunity explicit")
	expect(lines[2].contains("外力和持续伤害仍生效"), "No damage or push immunity claim")
	expect(var_to_bytes(cast) == old, "Preview does not mutate policy")
	expect(Preview.freeze_lines({"ok":true}).is_empty(), "Ordinary skills unchanged")
	print("Frost lock visual/text: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
