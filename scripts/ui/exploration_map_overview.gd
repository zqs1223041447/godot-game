extends Control
## Read-only projection of the same geometry and landmark states used by Main.
const PAPER := Color(0.08, 0.11, 0.12, 0.94)
const INK := Color("eee3c9")
const WALL := Color("778184")
const WAITING := Color("e3bc73")
const ACTIVE := Color("f68b70")
const CLEARED := Color("86c4a0")
const TARGET := Color("f5aad5")
const PLAYER := Color("8bdeed")
var _panel_style: StyleBoxFlat
var cleanup_hint: Dictionary = {}
var geometry: Dictionary = {}
var context: Dictionary = {}
var player_position := Vector2.ZERO
var player_facing := Vector2.RIGHT

func _ready() -> void:
	_panel_style = _background()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	# Keep the overview above HUD notices while reading the map.
	z_index = 10
	hide()

func open_map(value: Dictionary, world: Dictionary, position_value: Vector2, facing: Vector2) -> void:
	geometry = value.duplicate(true)
	update_live(world, position_value, facing)
	show()

func update_cleanup_hint(value: Dictionary) -> void:
	cleanup_hint = value.duplicate(true)
	if visible: queue_redraw()

func update_live(world: Dictionary, position_value: Vector2, facing: Vector2) -> void:
	context = world.duplicate(true)
	update_player(position_value, facing)

func update_player(position_value: Vector2, facing: Vector2) -> void:
	player_position = position_value
	player_facing = facing
	queue_redraw()

func map_rect() -> Rect2:
	var bounds: Rect2 = geometry.get("bounds", Rect2(0,0,1,1))
	var available := Rect2(26, 58, maxf(size.x-52,1), maxf(size.y-146,1))
	var scale_value := minf(available.size.x / bounds.size.x, available.size.y / bounds.size.y)
	var extent := bounds.size * scale_value
	return Rect2(available.get_center()-extent*0.5, extent)

func project(point: Vector2) -> Vector2:
	var bounds: Rect2 = geometry.bounds
	var area := map_rect()
	return area.position + (point-bounds.position) * (area.size / bounds.size)

func _text(at: Vector2, value: String, color: Color = INK, font_size: int = 13) -> void:
	draw_string(get_theme_default_font(), at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	if geometry.is_empty(): return
	draw_style_box(_panel_style, Rect2(Vector2.ZERO,size))
	_text(Vector2(22,30), "%s · 探索总览" % context.get("map_name",""), INK, 20)
	_text(Vector2(size.x-150,29), "Tab 收起 · 北 ↑", PLAYER)
	var area := map_rect()
	draw_rect(area, Color("202a2d"))
	draw_rect(area, Color("566366"), false, 1)
	for wall: Rect2 in geometry.get("walls",[]):
		draw_rect(Rect2(project(wall.position),project(wall.end)-project(wall.position)), WALL)
	for polygon: PackedVector2Array in geometry.get("module_polygons",[]):
		var projected := PackedVector2Array()
		for point: Vector2 in polygon: projected.append(project(point))
		draw_colored_polygon(projected, WALL)
	var landmarks: Dictionary = geometry.get("landmarks",{})
	if landmarks.has("entry"):
		var entry := project(landmarks.entry)
		draw_rect(Rect2(entry-Vector2(4,4),Vector2(8,8)), INK, false, 2)
		_text(entry+Vector2(-12,-10),"入口")
	var states: Dictionary = {}
	for state: Dictionary in context.get("outpost_states",[]): states[state.id] = state.state
	for outpost: Dictionary in landmarks.get("outposts",[]):
		var point := project(outpost.center)
		var state: String = states.get(outpost.id,"resident")
		var color := CLEARED if state == "cleared" else ACTIVE if state == "active" else WAITING
		draw_circle(point,5,color)
		if state == "cleared": draw_arc(point,8,0,TAU,24,color,1.0,true)
		_text(point+Vector2(-36,20),str(outpost.name),color,12)
	if landmarks.has("boss"):
		var boss := project(landmarks.boss.center)
		var color := CLEARED if context.get("boss_phase","") == "defeated" else ACTIVE
		draw_polyline(PackedVector2Array([boss+Vector2(0,-7),boss+Vector2(7,0),boss+Vector2(0,7),boss+Vector2(-7,0),boss+Vector2(0,-7)]),color,2,true)
		_text(boss+Vector2(-24,23),"首领已败" if context.get("boss_phase","")=="defeated" else "首领",color,12)
	_draw_cleanup_target()
	var player := project(player_position)
	var direction := player_facing.normalized()
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	var side := direction.orthogonal()
	draw_circle(player,9,Color("122c34"))
	draw_colored_polygon(PackedVector2Array([player+direction*9,player-direction*6+side*5,player-direction*6-side*5]),PLAYER)
	_text(player+Vector2(-6,27),"你",PLAYER)
	var y := size.y-61
	_text(Vector2(24,y),"● 未清驻点",WAITING)
	_text(Vector2(135,y),"● 交战 / 后续待生成",ACTIVE)
	_text(Vector2(310,y),"◎ 已清驻点",CLEARED)
	_text(Vector2(24,size.y-32),"灰色为实际障碍 · 标记为驻点原址 · 战斗继续",INK,13)
	_text(Vector2(24,size.y-12),cleanup_status(),TARGET,12)

func cleanup_status() -> String:
	match str(cleanup_hint.get("kind","inactive")):
		"target": return "余敌 %d · 圆环为最近余敌，需绕开障碍" % int(cleanup_hint.get("living_count",0))
		"waiting": return "后续怪物待出现，暂不标目标"
		"complete": return "地图已清理"
		"settlement": return "地图已清理 · 结算待保存"
		"blocked": return "清图状态异常，暂不标目标"
	return "剩余 1–5 个敌人时，标示最近目标"

func _draw_cleanup_target() -> void:
	if cleanup_hint.get("kind","") != "target": return
	var target: Dictionary = cleanup_hint.get("target",{})
	if not target.get("position") is Vector2: return
	var point := project(target.position)
	draw_arc(point,12,0,TAU,32,TARGET,2,true)
	draw_line(point-Vector2(4,0),point+Vector2(4,0),TARGET,2,true)
	draw_line(point-Vector2(0,4),point+Vector2(0,4),TARGET,2,true)
	var area := map_rect()
	var label_at := Vector2(clampf(point.x+16,area.position.x+6,area.end.x-84),clampf(point.y-8,area.position.y+16,area.end.y-8))
	_text(label_at,"最近余敌",TARGET,13)

func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = Color("728387")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style
