extends SceneTree
## Focused custom-draw font sizing and HUD synchronization; no native pixel claim.
const Overview = preload("res://scripts/ui/exploration_map_overview.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
func run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/godot-overview-font-") or not OS.get_user_data_dir().begins_with(isolated + "/"):
		quit(78); return
	var overview = Overview.new()
	overview.theme = preload("res://scripts/visuals/visual_theme.gd").create_theme()
	root.add_child(overview)
	check(overview.has_method("scaled_font_size"), "custom drawing has font preference support")
	if not overview.has_method("scaled_font_size"):
		overview.free(); finish(); return
	overview.size = Vector2(720,520)
	var geometry := {"bounds":Rect2(-100,-50,1000,700), "walls":[], "landmarks":{}}
	overview.open_map(geometry, {"map_name":"测试地图"}, Vector2(50,70),Vector2.RIGHT)
	var initial_rect: Rect2 = overview.map_rect()
	var initial_point: Vector2 = overview.project(Vector2(500,350))
	for scale_value: float in [1.0,1.1,1.2,1.0,1.2]:
		overview.font_scale = scale_value
		for base: int in [12,13,20]:
			check(overview.scaled_font_size(base)==roundi(base*scale_value), "authored font scales once %d %.1f" % [base,scale_value])
		check(overview.map_rect()==initial_rect and overview.project(Vector2(500,350))==initial_point,"font setting preserves map projection")
		check(overview.geometry==geometry and overview.player_position==Vector2(50,70),"font setting preserves map and player")
		for text_value: String in ["最近余敌","首领已败","入口","废墟驻点"]:
			for corner: Vector2 in [initial_rect.position, initial_rect.end, Vector2(initial_rect.end.x,initial_rect.position.y),Vector2(initial_rect.position.x,initial_rect.end.y)]:
				var placed: Vector2 = overview.map_text_position(corner,text_value,13)
				if scale_value > 1.0:
					check(initial_rect.encloses(overview.text_bounds(placed,text_value,13)),"large edge label stays within map")
		var footer: Array = overview.footer_baselines()
		var note: Rect2 = overview.text_bounds(Vector2(24,footer[1]),"灰色为实际障碍 · 标记为驻点原址 · 战斗继续",13)
		var legend: Rect2 = overview.text_bounds(Vector2(24,footer[0]),"● 未清驻点",13)
		check(legend.end.y+1 <= note.position.y,"legend and footnote do not overlap")
		var status: Rect2 = overview.text_bounds(Vector2(24,footer[2]),"剩余 1–5 个敌人时，标示最近目标",12)
		check(note.end.y + 1 <= status.position.y,"footer lines do not overlap")
		check(status.end.y <= overview.size.y,"footer descenders remain inside panel")
		if scale_value == 1.0: check(footer==[459.0,488.0,508.0],"100 percent keeps authored baselines")
	overview.free()
	root.size = Vector2i(1280,720)
	var arena = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	arena.set_process(false)
	var hud = arena.hud
	hud.set_process(false)
	await process_frame
	var before: PackedByteArray = var_to_bytes(arena.state.snapshot())
	var position: Vector2 = arena.player_pos
	var rng: int = arena.rng.state
	for index: int in [0,1,2,0,2]:
		hud._set_ui_scale(index % 3)
		hud._exploration_overview.hide()
		hud._set_font_scale(index)
		hud._layout_overview()
		check(is_equal_approx(hud._exploration_overview.font_scale,hud._preferences.font_scale),"hidden overview receives settings immediately")
		hud._exploration_overview.open_map(geometry,{"map_name":"测试地图"},position,Vector2.RIGHT)
		await process_frame
		check(hud._exploration_overview.scaled_font_size(20)==roundi(20*hud._preferences.font_scale),"reopen retains current preference")
		hud._apply_presentation()
		check(hud._exploration_overview.scaled_font_size(13)==roundi(13*hud._preferences.font_scale),"visible refresh does not compound scale")
	check(var_to_bytes(arena.state.snapshot())==before and arena.player_pos==position and arena.rng.state==rng,"presentation preserves build, world position and RNG")
	arena.queue_free()
	await process_frame
	finish()
func finish() -> void:
	print("Exploration overview font scale: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
