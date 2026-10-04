extends SceneTree
const Arena = preload("res://scripts/main.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/v044-native/"):
		quit(78)
		return
	var arena := Arena.new()
	root.add_child(arena)
	await process_frame
	if arena.state.crafting_balance() == 0:
		var uid := "item_%06d" % int(arena.state.snapshot().next_item_serial)
		arena.state._admit_reward_item(arena.state.Items.calibration_shard(uid, 16))
		arena.state.save_build(arena.build_save_path)
	arena.hud._town_view.open_service("skill_merchant")
