extends SceneTree
## Real rendering and native-input observer. Run only with isolated user data.
const Model = preload("res://scripts/build_state.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
var directory: String = "user://pierce-visual-qa"
var arena: Node2D
var report: Dictionary = {"inputs": [], "changes": []}
var interactive: bool = false
var finished: bool = false
var capture_busy: bool = false
var cast: Dictionary = {}
var mana_before: float
class Observer extends Node:
	var host: SceneTree
	func _input(event: InputEvent) -> void: host.observe_input(event)
	func _process(_delta: float) -> void: host.observe_frame()
func _initialize() -> void: call_deferred("run")
func save_report() -> void:
	var file := FileAccess.open(directory.path_join("native-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", true, true))
	file.close()
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native capture requires a rendering display")
		quit(2)
		return
	var isolated_data: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	if OS.get_name() != "Linux" or not isolated_data.begins_with("/tmp/godot-v014-native-") or not OS.get_user_data_dir().simplify_path().begins_with(isolated_data + "/"):
		push_error("Native fixture refuses non-isolated/default user data; use its explicit Linux QA launcher")
		quit(2)
		return
	if not OS.get_environment("GODOT_PIERCE_QA_DIR").is_empty(): directory = OS.get_environment("GODOT_PIERCE_QA_DIR")
	directory = ProjectSettings.globalize_path(directory)
	DirAccess.make_dir_recursive_absolute(directory)
	assert(Model.new().save_build() == OK)
	arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	arena.auto_fire = false
	arena.enemies.clear()
	arena.monster_runtime.reset()
	arena.projectile_runtime.cancel_all(arena.projectiles)
	arena.spawn_timer = 99999.0
	arena.player_pos = Vector2(400, 400)
	arena.player_facing = Vector2.RIGHT
	arena.state.slot_skill(0, "bolt")
	for index: int in range(6):
		var enemy: Dictionary = arena._spawn_monster("crawler", Vector2(800 + index * 45, 400), "ordinary")
		assert(not enemy.is_empty())
		enemy.spawn = 0.0
	arena.state.set_skill_supports("bolt", ["focus", "pierce"])
	arena.visual_settings.ui_scale = 1.1
	arena.visual_settings.font_scale = 1.2
	for size: Vector2i in [Vector2i(1280,720), Vector2i(2560,1440)]:
		root.size = size
		arena.hud._apply_presentation()
		arena.hud.open_panel("skills")
		arena.hud._panel_scroll.scroll_vertical = 0
		await capture("pierce-%dx%d-maxfont-top" % [size.x, size.y])
		arena.hud._panel_scroll.ensure_control_visible(arena.hud.find_child("SupportOption_pierce", true, false))
		await capture("pierce-%dx%d-maxfont-actions" % [size.x, size.y])
	if OS.get_cmdline_user_args().has("--capture-only"):
		print("PIERCE_NATIVE_CAPTURE_COMPLETE")
		quit(0)
		return
	arena.state.set_skill_supports("bolt", [])
	arena.hud.close_panel()
	root.size = Vector2i(1280,720)
	root.title = "v0.14 native QA - K, add pierce, Esc, 1"
	arena.visual_settings.ui_scale = 1.0
	arena.hud._apply_presentation()
	arena.hud.notify("隔离原生验收：K 为飞弹添加贯穿，Esc关闭后按1")
	arena.queue_redraw()
	report.fixture = {"user_data_dir": OS.get_user_data_dir(), "width":1280,"height":720,
		"changes": ["fresh isolated save", "slot bolt using production API", "six actual normal crawlers at controlled positions", "birth protection removed", "autofire and ambient spawns disabled", "simulation held for native input/capture and resumed by actual key1"],
		"enemy_stats_overridden":false, "invulnerability_override":false}
	var observer := Observer.new()
	observer.host = self
	root.add_child(observer)
	arena.state.changed.connect(on_state_changed)
	interactive = true
	save_report()
	print("PIERCE_NATIVE_READY")
func observe_input(event: InputEvent) -> void:
	if not interactive:return
	if event is InputEventKey and event.pressed and not event.echo:
		report.inputs.append({"key":OS.get_keycode_string(event.physical_keycode)})
		if event.physical_keycode == KEY_1 and not finished:
			cast = arena.state.get_skill_cast("bolt").duplicate(true)
			mana_before = arena.mana
			call_deferred("release_after_input")
	elif event is InputEventMouseButton and event.pressed:
		report.inputs.append({"button":event.button_index,"position": [event.position.x,event.position.y]})
		call_deferred("capture", "latest-native-click")
	save_report()
func on_state_changed() -> void: call_deferred("record_change")
func record_change() -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://build_save.json"))
	var current: Variant = JSON.parse_string(JSON.stringify(arena.state._snapshot()))
	var compiled: Dictionary = arena.state.get_skill_cast("bolt")
	report.changes.append({"links":arena.state.get_skill_supports("bolt"),"mana":compiled.mana,
		"pierce":compiled.recipe.pierce,"save_equals_snapshot":saved==current})
	save_report()
	print("PIERCE_NATIVE_CHANGE ", JSON.stringify(report.changes.back()))
func release_after_input() -> void:
	if arena.projectiles.is_empty():return
	report.cast = {"initial_count":arena.projectiles.size(),"mana_before":mana_before,"mana_after":arena.mana,
		"paid":mana_before-arena.mana,"expected_mana":cast.mana,"compiled_pierce":cast.recipe.pierce}
	arena.set_process(true)
	save_report()
func observe_frame() -> void:
	if not interactive or finished or cast.is_empty():return
	var hits: Dictionary = {}
	for record: Dictionary in arena.damage_trace:
		hits[record.projectile_id] = int(hits.get(record.projectile_id,0))+1
	var maximum: int = 0
	for count: int in hits.values():maximum = maxi(maximum,count)
	if maximum < 4:return
	finished = true
	arena.set_process(false)
	report.hits = {"records":arena.damage_trace.duplicate(true),"counts_by_projectile":hits,"maximum":maximum,
		"expected_single_hit":Damage.resolve(cast.packets.projectile,cast.snapshot.modifiers).total,
		"elapsed":arena.elapsed,"living":arena.enemies.size()}
	save_report()
	call_deferred("capture","actual-key1-four-targets")
	print("PIERCE_NATIVE_HIT_PASS ", JSON.stringify(report.hits))
func capture(label: String) -> void:
	if capture_busy:return
	capture_busy = true
	for unused: int in range(10):await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK)
	print("PIERCE_NATIVE_CAPTURE ",label)
	capture_busy = false
