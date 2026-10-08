extends Control
## Original material-led test settlement, drawn independently from combat rules.
signal service_requested(id: String)
const INK = Color("493c29")
const WOOD = Color("826343")
const CLOTH = [Color("89714d"),Color("8b6250"),Color("6f8260"),Color("777499"),Color("786553"),Color("8c7e61")]
var _centers: Array[Vector2] = []
var _buttons: Array[Button] = []
var _ids: Array[String] = []
func setup(services: Array) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for service: Dictionary in services:
		var button := Button.new()
		button.text = str(service.name)
		button.add_theme_font_size_override("font_size",13)
		button.tooltip_text = str(service.description)
		button.pressed.connect(func(): service_requested.emit(str(service.id)))
		add_child(button)
		_buttons.append(button)
		_ids.append(str(service.id))
	resized.connect(_layout)
	_layout()
func _layout() -> void:
	_centers.clear()
	for index: int in range(_buttons.size()):
		var center := Vector2(size.x*(0.30+0.25*float(index%3)), size.y*(0.29 if index<3 else 0.59))
		_centers.append(center)
		_buttons[index].position = center+Vector2(-66,37)
		_buttons[index].size = Vector2(132,28)
	queue_redraw()
func set_test_mode(testing: bool) -> void:
	for index: int in range(_buttons.size()):
		_buttons[index].disabled = not testing and _ids[index] not in ["map_device", "crafter", "passive_reset", "skill_merchant", "equipment_merchant", "jewel_merchant"]
		if _buttons[index].disabled: _buttons[index].tooltip_text = "免费供应仅在独立测试城镇开放。"
func _draw() -> void:
	for index: int in range(_centers.size()):
		var center := _centers[index]
		draw_ellipse_shadow(center+Vector2(0,36))
		draw_rect(Rect2(center+Vector2(-53,-4),Vector2(106,38)),WOOD)
		for x: float in [-49.0,49.0]:
			draw_line(center+Vector2(x,-34),center+Vector2(x,33),INK,5.0,true)
		var roof := PackedVector2Array([center+Vector2(-62,-25),center+Vector2(-42,-47),center+Vector2(42,-47),center+Vector2(62,-25)])
		draw_colored_polygon(roof,CLOTH[index])
		roof.append(roof[0])
		draw_polyline(roof,INK,2.0,true)
		for x: int in range(-45,50,18): draw_line(center+Vector2(x,-44),center+Vector2(x*1.22,-26),Color("ddc69c"),3.0,true)
		# A readable shopkeeper silhouette behind the counter.
		draw_circle(center+Vector2(0,-11),7,Color("caa780"))
		draw_rect(Rect2(center+Vector2(-10,-3),Vector2(20,20)),CLOTH[index].darkened(0.18))
		if _ids[index] == "map_device":
			draw_circle(center+Vector2(28,14),14,Color("ada58d"))
			draw_arc(center+Vector2(28,14),11,0,TAU,24,INK,2.0,true)
			draw_line(center+Vector2(16,14),center+Vector2(40,14),INK,1.0,true)
		else:
			for j: int in range(3):
				var pos := center+Vector2(-35+j*29,21)
				draw_rect(Rect2(pos-Vector2(7,9),Vector2(14,12)),Color("c2a477"))
			draw_line(center+Vector2(-49,31),center+Vector2(49,31),Color("b09367"),2.0,true)
func draw_ellipse_shadow(center: Vector2) -> void:
	var points := PackedVector2Array()
	for index: int in range(32):
		var angle: float = TAU*float(index)/32.0
		points.append(center+Vector2(cos(angle)*66,sin(angle)*10))
	draw_colored_polygon(points,Color(0.16,0.14,0.10,0.2))
