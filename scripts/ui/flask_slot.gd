class_name FlaskSlot
extends Button
## A view of one canonical flask slot. Runtime charges remain owned by the arena.
signal item_hovered(uid: String, anchor: Rect2)
signal hover_left
signal move_requested(uid: String, destination: Dictionary, revision: int)
signal remove_requested(uid: String)
signal use_requested(slot_id: String)

const Style = preload("res://scripts/ui/dock_visual_style.gd")
const IconLayout = preload("res://scripts/ui/gem_icon.gd")
const Tooltips = preload("res://scripts/ui/crafting_controls.gd")
var model: RefCounted
var slot_id := "flask_1"
var editing := true
var status: Dictionary = {}
var _icon: Texture2D
static var _textures: Dictionary = {}

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(30,32) if editing else Vector2(48,48)
	add_theme_stylebox_override("normal",Style.surface(Color("dfd1b3"),2.0))
	add_theme_stylebox_override("hover",Style.surface(Color("f0dfb7"),2.0))
	add_theme_stylebox_override("pressed",Style.surface(Color("ccb78b"),2.0))
	add_theme_stylebox_override("disabled",Style.surface(Color("d2c6ad"),2.0))
	pressed.connect(func():
		if not editing: use_requested.emit(slot_id))
	mouse_entered.connect(func():
		var uid := str(status.get("uid",""))
		if editing and not uid.is_empty(): item_hovered.emit(uid,get_global_rect()))
	mouse_exited.connect(func(): hover_left.emit())

func set_status(value: Dictionary) -> void:
	if status == value: return
	status = value.duplicate(true)
	var path := str(status.get("icon_path",""))
	if not path.is_empty() and not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	_icon = _textures.get(path) as Texture2D
	disabled = not editing and not bool(status.get("can_use",false))
	var uid := str(status.get("uid",""))
	if uid.is_empty():
		tooltip_text = "空药剂槽"
	elif not editing:
		tooltip_text = "%s · Alt+%s\n充能 %d/%d" % [status.get("name","药剂"),slot_id.get_slice("_",1),int(status.get("charges",0)),int(status.get("max_charges",30))]
		var reason := str(status.get("reason",""))
		if not reason.is_empty(): tooltip_text += "\n"+reason
	else:
		tooltip_text = ""
	queue_redraw()

func _draw() -> void:
	var footer := 13.0 if not editing else 0.0
	if _icon != null:
		var bounds := Rect2(Vector2(2,2),Vector2(size.x-4,size.y-4-footer))
		var fit: Rect2 = IconLayout.aspect_fit_rect(_icon.get_size(),bounds)
		draw_texture_rect(_icon,fit,false,Color(1,1,1,0.65 if disabled else 1.0))
	if not editing:
		var font := get_theme_default_font()
		draw_string(font,Vector2(2,size.y-4),"Alt+"+slot_id.get_slice("_",1),HORIZONTAL_ALIGNMENT_CENTER,size.x-4,9,Color("44301f"))
		if not str(status.get("uid","")).is_empty():
			var ratio := clampf(float(status.get("charges",0))/maxf(1,float(status.get("max_charges",30))),0,1)
			draw_rect(Rect2(2,size.y-3,size.x-4,2),Color("897852"))
			draw_rect(Rect2(2,size.y-3,(size.x-4)*ratio,2),Color("b74136") if status.get("resource") == "health" else Color("486da0"))
			draw_string(font,Vector2(2,11),str(status.get("charges",0)),HORIZONTAL_ALIGNMENT_RIGHT,size.x-5,9,Color("44301f"))
			if bool(status.get("active",false)):
				draw_rect(Rect2(1,1,size.x-2,size.y-2),Color("ad803d"),false,2)

func _get_drag_data(_at: Vector2) -> Variant:
	var uid := str(status.get("uid",""))
	if not editing or uid.is_empty() or model == null: return null
	return {"type":"unified_item","uid":uid,"revision":model.revision(),"grab_offset":Vector2i.ZERO}

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not editing or model == null or not data is Dictionary or data.size()!=4: return false
	if data.get("type")!="unified_item" or not data.get("uid") is String or not data.get("revision") is int or not data.get("grab_offset") is Vector2i: return false
	return model.can_move_item(data.uid,{"kind":"flask_slot","slot_id":slot_id},data.revision)

func _drop_data(at: Vector2,data: Variant) -> void:
	if _can_drop_data(at,data): move_requested.emit(data.uid,{"kind":"flask_slot","slot_id":slot_id},data.revision)

func _gui_input(event: InputEvent) -> void:
	if editing and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var uid := str(status.get("uid",""))
		if not uid.is_empty(): remove_requested.emit(uid)
		accept_event()

func _make_custom_tooltip(text_value: String) -> Object:
	if text_value.strip_edges().is_empty() or (editing and not str(status.get("uid","")).is_empty()): return null
	return Tooltips.wrapped_tooltip(self,text_value)
