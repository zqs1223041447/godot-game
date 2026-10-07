extends SceneTree
## Run this same bounded probe with --path at v119 and v120; compare raw bytes.
const Runtime = preload("res://scripts/combat/telegraphed_area_runtime.gd")
const Monsters = preload("res://scripts/monsters/monster_catalog.gd")
const Renderer = preload("res://scripts/visuals/telegraph_renderer.gd")
func _initialize() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/godot-v120-") or OS.get_cmdline_user_args().size() != 1: quit(78); return
	var traces: Dictionary = {}
	for pattern: String in ["garden_slam","ruins_mark","sunwell_echo","ginkgo_shelter_slam"]:
		var source := {"id":1,"root_id":1,"generation":0,"template_id":"rift_warden","rarity":"boss",
			"map_boss_attack_id":pattern,"pos":Vector2(100,150),"health":100.0,"spawn":0.0,
			"death_processed":false,"damage":100.0,"attack_speed":Monsters.BASE_ATTACK_SPEED,
			"contact_weights":{"physical":0.5,"fire":0.3,"cold":0.2}}
		var runtime := Runtime.new(); var policy: Dictionary = Monsters.telegraph_policy(source)
		var trace: Array = [policy,runtime.start(source,Vector2(200,250),policy.profile,pattern)]
		for delta: float in [0.4,0.4,0.4,0.4,0.4,0.4,2.0]:
			var events: Array = runtime.advance(delta,[source],true)
			var state: Dictionary = runtime.state_for(1)
			trace.append([events,state,Renderer.primitives([state]),runtime.has_timed_sequence_actions()])
		traces[pattern] = trace
	var file := FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
	file.store_buffer(var_to_bytes(traces)); file.close()
	print("RUINS_LEGACY_PROBE four old map trajectories captured; exact raw events, snapshots, policies and primitives")
	quit(0)
