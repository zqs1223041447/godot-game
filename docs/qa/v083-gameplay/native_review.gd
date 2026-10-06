extends SceneTree
## Root owns the one native window. Isolated static review, not natural combat.
const Fixture = preload("res://docs/qa/v083-gameplay/ginkgo_fixture.gd")
var arena: Node
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/v083-ginkgo-native-"):
		push_error("Native fixture requires a dedicated /tmp/v083-ginkgo-native-* save directory")
		quit(78)
		return
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	var result: Dictionary = Fixture.open_test_map(arena)
	if not result.ok:
		push_error("Real native entry failed: " + JSON.stringify(result))
		quit(1)
		return
	if OS.get_environment("GINKGO_NATIVE_MODE") == "warning":
		var boss: Dictionary = Fixture.natural_boss(arena)
		if boss.is_empty(): push_error("Full 36-root natural boss admission failed"); quit(1); return
		boss.spawn = 0.0
		boss.attack_timer = 0.0
		boss.knockback = Vector2.ZERO
		arena.player_pos = boss.pos + Vector2(0, 140)
		arena._start_enemy_telegraphs()
		arena._advance_enemy_telegraphs(0.7)
		var attack: Dictionary = arena.telegraphs.state_for(boss.id)
		if attack.is_empty() or attack.visual_pattern != "ginkgo_shelter_slam":
			push_error("Authoritative warning missing"); quit(1); return
		print("GINKGO_NATIVE_WARNING ", JSON.stringify(attack))
	Fixture.pause(arena)
	arena.hud._process(0.0)
	arena.queue_redraw()
	print("GINKGO_NATIVE_READY controlled static fixture; full roster retained; independent test save; mode=", OS.get_environment("GINKGO_NATIVE_MODE"))
