extends SceneTree
## Real display capture of actual main. Isolated fixture, never a production save.
var arena: Node2D
var guard: Dictionary
var directory: String
var interactive: bool = false
var running: bool = false
var completed: bool = false
var records: Array[Dictionary] = []
var inputs: Array[Dictionary] = []

class Observer extends Node:
	var host: SceneTree
	func _input(event: InputEvent) -> void: host.observe(event)
	func _process(_delta: float) -> void: host.poll()

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var data: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	directory = OS.get_environment("GODOT_TELEGRAPH_QA_OUT")
	if OS.get_name() != "Linux" or DisplayServer.get_name() == "headless" or not data.begins_with("/tmp/godot-v016-native") or not OS.get_user_data_dir().begins_with(data + "/") or not directory.is_absolute_path():
		printerr("Native telegraph fixture requires isolated Linux storage and a real display")
		quit(78)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280,720)
	root.position = Vector2i(10,30)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	interactive = OS.get_cmdline_user_args().has("--interactive")
	if interactive:
		prepare()
		root.title = "v0.16 native dodge QA - hold D to move out of the warning"
		var observer := Observer.new()
		observer.host = self
		root.add_child(observer)
		print("TELEGRAPH_NATIVE_INPUT_READY")
		await capture("native-before")
		return
	for size: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440)]:
		root.size = size
		for level: int in [2,0]:
			prepare()
			arena.visual_settings.effects_level = level
			arena._start_enemy_telegraphs()
			for frame: int in range(21): arena.tick(1.0/60.0)
			await capture("warning-%d-%d" % [size.x,level])
			for frame: int in range(21): arena.tick(1.0/60.0)
			assert(arena.telegraph_trace.size()==1 and arena.telegraph_trace[0].applied)
			await capture("impact-%d-%d" % [size.x,level])
			prepare()
			arena.visual_settings.effects_level = level
			arena._start_enemy_telegraphs()
			# This phase is a controlled position sample, not a physical input claim.
			arena.player_pos += Vector2(168,0)
			for frame: int in range(42): arena.tick(1.0/60.0)
			assert(arena.telegraph_trace.size()==1 and not arena.telegraph_trace[0].inside)
			await capture("dodge-%d-%d" % [size.x,level])
	write_records()
	print("TELEGRAPH_MAIN_CAPTURE_COMPLETE ",records.size())
	quit(0)

func prepare() -> void:
	arena.restart_run()
	arena.set_process(false)
	arena.hud.close_panel()
	arena.auto_fire = false
	arena.spawn_timer = 99999.0
	arena.enemies.clear()
	arena.wave = 3
	arena.elapsed = 60.0
	arena.ordinary_admissions = 0
	arena.rng.seed = 1600316
	guard = {}
	for index: int in range(8):
		var enemy: Dictionary = arena._spawn_enemy()
		if enemy.template_id == "ember_guard": guard = enemy
	assert(not guard.is_empty())
	arena.enemies.clear()
	arena.enemies.append(guard)
	arena.player_pos = arena.ARENA.get_center()
	guard.pos = arena.player_pos + Vector2(130,0)
	guard.spawn = 0.0
	guard.attack_timer = 0.0
	arena.invulnerable = 0.0
	arena.rings.clear()
	arena.particles.clear()
	arena.visual_cues.reset()
	arena.hud._toast_left = 0
	arena.hud._toast.hide()
	arena.queue_redraw()

func observe(event: InputEvent) -> void:
	if not interactive or completed: return
	if event is InputEventKey and not event.echo:
		inputs.append({"key":OS.get_keycode_string(event.physical_keycode),"pressed":event.pressed})
		if event.pressed and (event.physical_keycode==KEY_D or event.keycode==KEY_D) and not running:
			running = true
			arena._start_enemy_telegraphs()
			arena.set_process(true)
			print("TELEGRAPH_NATIVE_INPUT_STARTED")

func poll() -> void:
	if not interactive or not running or completed or arena.telegraph_trace.is_empty(): return
	completed = true
	arena.set_process(false)
	var event: Dictionary = arena.telegraph_trace.back()
	print("TELEGRAPH_NATIVE_DODGE ",not event.inside," distance=",Vector2(event.center).distance_to(arena.player_pos))
	capture.call_deferred("native-after")

func capture(label: String) -> void:
	arena.queue_redraw()
	for frame: int in range(8): await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK)
	var record: Dictionary = {"label":label,"resolution":[root.size.x,root.size.y],"effects":arena.visual_settings.effects_level,
		"health":arena.health,"shield":arena.shield,"player":[arena.player_pos.x,arena.player_pos.y],
		"source_id":guard.id,"source_health":guard.health,"source_damage":guard.damage,
		"natural_admissions":arena.ordinary_admissions,"traces":preload("res://tools/export_reference.gd").clean(arena.telegraph_trace),
		"states":preload("res://tools/export_reference.gd").clean(arena.telegraph_visual_states())}
	records.append(record)
	write_records()
	print("TELEGRAPH_MAIN_CAPTURE ",label)

func write_records() -> void:
	var file := FileAccess.open(directory.path_join("native-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"interactive":interactive,"inputs":inputs,"records":records,
		"fixture_changes":["isolated fresh save","natural eighth admission at wave3","other sources removed to isolate one attack","source/player positioned","birth and initial attack delay skipped","auto fire and new spawning disabled","render phases held between fixed ticks"],
		"damage_health_shield_stats_modified":false},"\t",true,true))
	file.close()
