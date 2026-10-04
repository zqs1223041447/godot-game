extends SceneTree
const Arena = preload("res://scripts/main.gd")
const Profiles = preload("res://scripts/monsters/telegraph_profiles.gd")
class PreviewArena extends Arena:
	var preview_telegraphs: Array[Dictionary] = []
	func telegraph_visual_states() -> Array[Dictionary]: return preview_telegraphs
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/v045-native/"):
		quit(78)
		return
	var arena := PreviewArena.new()
	root.add_child(arena)
	await process_frame
	arena.leave_normal_town(int(arena.world_context().revision))
	arena.set_process(false)
	var index := 0
	for enemy: Dictionary in arena.enemies:
		enemy.pos = arena.player_pos + Vector2(120 + index * 90, -55 + index * 70)
		enemy.spawn = 0.0
		arena.burn_runtime.apply("monster", int(enemy.id), 0, 12.0, 3.0, 0.0)
		index += 1
	arena.invulnerable = 0.0
	arena.burn_runtime.apply("player", 0, 1, 6.0, 3.0, 0.0)
	arena.preview_telegraphs = [{"source_id":1,"center":arena.player_pos + Vector2(-200,0),"phase":"windup","elapsed":0.4,"profile":Profiles.DEFAULTS.duplicate(true),"visual_pattern":"ember_burn"}]
	arena.state.award_gem("support:ignite")
	arena.retained_actors.sync(arena)
	arena.queue_redraw()
	arena.foreground_layer.queue_redraw()
